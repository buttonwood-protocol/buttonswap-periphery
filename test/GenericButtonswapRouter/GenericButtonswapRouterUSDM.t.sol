// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IGenericButtonswapRouter} from "../../src/interfaces/IButtonswapRouter/IGenericButtonswapRouter.sol";
import {IGenericButtonswapRouterErrors} from "../../src/interfaces/IButtonswapRouter/IGenericButtonswapRouterErrors.sol";
import {GenericButtonswapRouter} from "../../src/GenericButtonswapRouter.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {ButtonswapLibrary} from "../../src/libraries/ButtonswapLibrary.sol";
import {ButtonswapOperations} from "../../src/libraries/ButtonswapOperations.sol";
import {PairMath} from "buttonswap-periphery_buttonswap-core/libraries/PairMath.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {MockWeth} from "./../mocks/MockWeth.sol";
import {MockButtonToken} from "./../mocks/MockButtonToken.sol";
import {IUSDM} from "../../src/interfaces/IUSDM.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IButtonswapPairErrors} from
    "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPairErrors.sol";
import {console} from "buttonswap-periphery_forge-std/console.sol";

contract GenericButtonswapRouterUSDMTest is Test, IGenericButtonswapRouterErrors {
    string constant ARBITRUM_RPC_URL = "https://arb1.arbitrum.io/rpc";
    address constant USDM_MINTER = 0x48AEB395FB0E4ff8433e9f2fa6E0579838d33B62;
    uint256 constant BPS = 10_000;

    address public feeToSetter;
    address public isCreationRestrictedSetter;
    address public isPausedSetter;
    address public paramSetter;
    address public userA;
    uint256 public userAPrivateKey;
    MockRebasingERC20 public tokenB;
    IWETH public weth;
    ButtonswapFactory public buttonswapFactory;
    GenericButtonswapRouter public genericButtonswapRouter;

    IERC20 public usdm;

    // Required function for receiving ETH refunds
    receive() external payable {}

    function mintUsdm(address receiver, uint256 amount) internal {
        vm.prank(USDM_MINTER);
        IUSDM(address(usdm)).mint(receiver, amount);
    }

    // Utility function for creating and initializing pairs with poolUsdm:poolB price ratio. Does not use ButtonwoodRouter
    function createAndInitializePair(MockRebasingERC20 tokenB1, uint256 poolUsdm, uint256 poolB)
        private
        returns (IButtonswapPair pair, uint256 liquidityOut)
    {
        pair = IButtonswapPair(buttonswapFactory.createPair(address(usdm), address(tokenB1)));
        mintUsdm(address(this), poolUsdm);
        usdm.approve(address(pair), poolUsdm);
        tokenB1.mint(address(this), poolB);
        tokenB1.approve(address(pair), poolB);

        if (pair.token0() == address(usdm)) {
            liquidityOut = pair.mint(poolUsdm, poolB, address(this));
        } else {
            liquidityOut = pair.mint(poolB, poolUsdm, address(this));
        }
    }

    function setUp() public {
        uint256 arbitrumFork = vm.createFork(ARBITRUM_RPC_URL);
        vm.selectFork(arbitrumFork);

        feeToSetter = makeAddr("feeToSetter");
        isCreationRestrictedSetter = makeAddr("isCreationRestrictedSetter");
        isPausedSetter = makeAddr("isPausedSetter");
        paramSetter = makeAddr("paramSetter");
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);
        weth = new MockWeth();
        buttonswapFactory = new ButtonswapFactory(
            feeToSetter, isCreationRestrictedSetter, isPausedSetter, paramSetter, "Token Name", "SYMBOL"
        );
        genericButtonswapRouter = new GenericButtonswapRouter(address(buttonswapFactory), address(0), address(weth));

        usdm = IERC20(0x59D9356E565Ab3A36dD77763Fc0d87fEaf85508C);
    }

    function test_validateUSDM() public {
        assertEq(usdm.symbol(), "USDM", "USDM symbol should be USDM");
    }

    function test_transfer(uint256 balance, uint256 transferAmount) public {
        // Ensure we don't mint more than the max supply possible. Only interested to up to uint112
        balance = bound(balance, 1, type(uint112).max);
        mintUsdm(address(this), balance);

        // Validaate that the balance received is within 2 of the minted amount
        assertApproxEqAbs(usdm.balanceOf(address(this)), balance, 2, "Initial balance is within 2 of minting amount");

        // Transfer from address(this) to userA and validate amount received
        transferAmount = bound(transferAmount, 0, usdm.balanceOf(address(this)));
        usdm.transfer(userA, transferAmount);
        assertApproxEqAbs(
            usdm.balanceOf(userA), transferAmount, 2, "Received amount is always within 2 of transferAmount"
        );
    }

    function test_transfer2(uint256 balance, uint256 transferAmount) public {
        // Ensure we don't mint more than the max supply possible. Only interested to up to uint112
        balance = bound(balance, 1, type(uint112).max);
        mintUsdm(address(this), balance);

        // Calculate the original shares and the shares to transfer
        uint256 originalShares = IUSDM(address(usdm)).sharesOf(address(this));
        transferAmount = bound(transferAmount, 0, usdm.balanceOf(address(this)));
        uint256 transferredShares = IUSDM(address(usdm)).convertToShares(transferAmount);

        // Transfer from address(this) to userA
        usdm.transfer(userA, transferAmount);

        // Calculate the expected balance using the difference in shares and converting to tokens
        uint256 expectedBalance = IUSDM(address(usdm)).convertToTokens(originalShares - transferredShares);

        // Calculate new user balance by converting transferredShares to tokens
        uint256 expectedUserBalance = IUSDM(address(usdm)).convertToTokens(transferredShares);

        assertEq(
            usdm.balanceOf(address(this)),
            expectedBalance,
            "Curve pool balance should exactly equal expectedCurvePoolBalance"
        );
        assertEq(usdm.balanceOf(userA), expectedUserBalance, "User balance should exactly equal expectedUserBalance");
    }

    function test_swapExactTokensForTokens_singleSwapUSDMIn(
        uint256 poolUsdm,
        uint256 poolB,
        uint256 amountIn,
        uint256 amountOutMin
    ) public {
        // Regenerating tokenB to mix up the token order
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);

        // Minting enough for minimum liquidity requirement
        poolUsdm = bound(poolUsdm, 10000, type(uint112).max - 3);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        // Bounding below by 3 since 1 and 2 can both result in the router receiving 0 usdm
        amountIn = bound(amountIn, 3, type(uint112).max - poolUsdm);

        // Creating the pair with poolUsdm:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenB, poolUsdm, poolB);
        // Update poolUsdm to be accurate
        poolUsdm = usdm.balanceOf(address(pair));

        // Estimating how much output a trade would give
        uint256 routerReceivingAmount =
            IUSDM(address(usdm)).convertToTokens(IUSDM(address(usdm)).convertToShares(amountIn));
        uint256 pairReceivingAmount =
            IUSDM(address(usdm)).convertToTokens(IUSDM(address(usdm)).convertToShares(routerReceivingAmount));
        uint256 expectedAmountOut = ButtonswapLibrary.getAmountOut(pairReceivingAmount, poolUsdm, poolB);
        // Making sure that expectedAmountOut is positive
        vm.assume(expectedAmountOut > 0);
        // Ensuring amountOutMin bounded below expectedAmountOut
        amountOutMin = bound(amountOutMin, 0, expectedAmountOut);

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.USDM_SWAP, address(tokenB), "");

        // Approving the router to take at most amountIn usdm
        mintUsdm(address(this), amountIn);
        usdm.approve(address(genericButtonswapRouter), amountIn);

        // Doing a single swap
        uint256[] memory amounts = genericButtonswapRouter.swapExactTokensForTokens(
            address(usdm), amountIn, amountOutMin, swapSteps, address(this), block.timestamp + 1
        );

        // Validating the correct amounts
        assertEq(amounts[0], amountIn, "First amount should be amountIn");
        assertEq(amounts[1], expectedAmountOut, "Last amount should be expectedAmountOut");
    }

    function test_swapExactTokensForTokens_singleSwapUSDMOut(
        uint256 poolUsdm,
        uint256 poolB,
        uint256 amountIn,
        uint256 amountOutMin
    ) public {
        // Regenerating tokenB to mix up the token order
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);

        // Minting enough for minimum liquidity requirement
        poolUsdm = bound(poolUsdm, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max - 1);

        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountIn = bound(amountIn, 1, type(uint112).max - poolB);

        // Creating the pair with poolUsdm:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenB, poolUsdm, poolB);
        // Update poolUsdm to be accurate
        poolUsdm = usdm.balanceOf(address(pair));

        // Estimating how much output a trade would give
        uint256 expectedAmountOut = ButtonswapLibrary.getAmountOut(amountIn, poolB, poolUsdm);

        // Making sure that expectedAmountOut is positive
        vm.assume(expectedAmountOut > 0);
        // Ensuring amountOutMin bounded below expectedAmountOut
        amountOutMin = bound(amountOutMin, 0, expectedAmountOut);

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.SWAP, address(usdm), "");

        // Approving the router to take at most amountIn tokenB
        tokenB.mint(address(this), amountIn);
        tokenB.approve(address(genericButtonswapRouter), amountIn);

        // Doing a single swap
        uint256[] memory amounts = genericButtonswapRouter.swapExactTokensForTokens(
            address(tokenB), amountIn, amountOutMin, swapSteps, address(this), block.timestamp + 1
        );

        // Validating the correct amounts
        assertEq(amounts[0], amountIn, "First amount should be amountIn");
        assertEq(amounts[1], expectedAmountOut, "Last amount should be expectedAmountOut");
    }

    function test_swapTokensForExactTokens_singleSwapUSDMIn(
        uint256 poolUsdm,
        uint256 poolB,
        uint256 amountOut,
        uint256 amountInMax
    ) public {
        // Regenerating tokenB to mix up the token order
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);

        // Minting enough for minimum liquidity requirement
        poolUsdm = bound(poolUsdm, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Ensuring that amountOut is bounded to avoid errors/overflows/underflows. Must be less than poolB
        amountOut = bound(amountOut, 1000, poolB - 1);

        // Creating the pair with poolUsdm:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenB, poolUsdm, poolB);
        // Update poolUsdm to be accurate
        poolUsdm = usdm.balanceOf(address(pair));

        // Estimating how much input a trade would take
        uint256 expectedAmountIn = ButtonswapLibrary.getAmountIn(amountOut, poolUsdm, poolB) + 4;
        // Making sure that expectedAmountIn is positive but not outside of possible range
        vm.assume(expectedAmountIn > 0);
        vm.assume(expectedAmountIn < type(uint112).max - poolUsdm);
        // Ensuring amountInMax bounded above expectedAmountIn
        amountInMax = bound(amountInMax, expectedAmountIn, type(uint112).max);

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.USDM_SWAP, address(tokenB), "");

        // Approving the router to take at most amountInMax usdm
        mintUsdm(address(this), amountInMax);
        usdm.approve(address(genericButtonswapRouter), amountInMax);

        // Doing a single swap
        uint256[] memory amounts = genericButtonswapRouter.swapTokensForExactTokens(
            address(usdm), amountOut, amountInMax, swapSteps, address(this), block.timestamp + 1
        );

        // Validating the correct amounts
        assertEq(amounts[0], expectedAmountIn, "First amount should be expectedAmountIn");
        // Need to use `Ge()` instead of `Eq()`.
        // On this test, there is no extraneous input, but precision loss of uint112s can cause: getAmountOut(getAmountIn(amountOut)) > amountOut
        // Thus the amount received will actually be greater than or equal to amountOut
        assertGe(amounts[1], amountOut, "Last amount should be [AT LEAST] amountOut");
    }

    function test_swapTokensForExactTokens_singleSwapUSDMOut(
        uint256 poolUsdm,
        uint256 poolB,
        uint256 amountOut,
        uint256 amountInMax
    ) public {
        // Regenerating tokenB to mix up the token order
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);

        // Minting enough for minimum liquidity requirement
        poolUsdm = bound(poolUsdm, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max - 1);

        // Creating the pair with poolUsdm:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenB, poolUsdm, poolB);
        // Update poolUsdm to be accurate
        poolUsdm = usdm.balanceOf(address(pair));

        // Ensuring that amountOut is bounded to avoid errors/overflows/underflows. Must be less than poolB
        amountOut = bound(amountOut, 1000, poolUsdm - 1);

        // Estimating how much input a trade would take
        uint256 expectedAmountIn = ButtonswapLibrary.getAmountIn(amountOut, poolB, poolUsdm);
        // Making sure that expectedAmountIn is positive but not outside of possible range
        vm.assume(expectedAmountIn > 0);
        vm.assume(expectedAmountIn < type(uint112).max - poolB);
        // Ensuring amountInMax bounded above expectedAmountIn
        amountInMax = bound(amountInMax, expectedAmountIn, tokenB.mintableBalance());

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.SWAP, address(usdm), "");

        // Approving the router to take at most amountInMax tokenA
        tokenB.mint(address(this), amountInMax);
        tokenB.approve(address(genericButtonswapRouter), amountInMax);

        // Doing a single swap
        uint256[] memory amounts = genericButtonswapRouter.swapTokensForExactTokens(
            address(tokenB), amountOut, amountInMax, swapSteps, address(this), block.timestamp + 1
        );

        // Validating the correct amounts
        assertEq(amounts[0], expectedAmountIn, "First amount should be expectedAmountIn");
        // Need to use `Ge()` instead of `Eq()`.
        // On this test, there is no extraneous input, but precision loss of uint112s can cause: getAmountOut(getAmountIn(amountOut)) > amountOut
        // Thus the amount received will actually be greater than or equal to amountOut
        assertGe(amounts[1], amountOut, "Last amount should be [AT LEAST] amountOut");
    }
}
