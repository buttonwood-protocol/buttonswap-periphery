// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IGenericButtonswapRouter} from "../src/interfaces/IButtonswapRouter/IGenericButtonswapRouter.sol";
import {IGenericButtonswapRouterErrors} from "../src/interfaces/IButtonswapRouter/IGenericButtonswapRouterErrors.sol";
import {GenericButtonswapRouter} from "../src/GenericButtonswapRouter.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {ButtonswapLibrary} from "../src/libraries/ButtonswapLibrary.sol";
import {ButtonswapOperations} from "../src/libraries/ButtonswapOperations.sol";
import {PairMath} from "buttonswap-periphery_buttonswap-core/libraries/PairMath.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {MockWeth} from "./mocks/MockWeth.sol";
import {MockButtonToken} from "./mocks/MockButtonToken.sol";

contract GenericButtonswapRouterTest is Test, IGenericButtonswapRouterErrors {
    uint256 constant BPS = 10_000;

    address public feeToSetter;
    uint256 public feeToSetterPrivateKey;
    address public isCreationRestrictedSetter;
    uint256 public isCreationRestrictedSetterPrivateKey;
    address public isPausedSetter;
    uint256 public isPausedSetterPrivateKey;
    address public paramSetter;
    uint256 public paramSetterPrivateKey;
    address public userA;
    uint256 public userAPrivateKey;
    MockRebasingERC20 public tokenA;
    MockRebasingERC20 public tokenB;
    MockButtonToken public buttonTokenA;
    IWETH public weth;
    ButtonswapFactory public buttonswapFactory;
    GenericButtonswapRouter public genericButtonswapRouter;

    // Utility function for creating and initializing pairs with poolA:poolB price ratio. Does not use ButtonwoodRouter
    function createAndInitializePair(MockRebasingERC20 tokenA1, MockRebasingERC20 tokenB1, uint256 poolA, uint256 poolB)
        private
        returns (IButtonswapPair pair, uint256 liquidityOut)
    {
        pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA1), address(tokenB1)));
        tokenA1.mint(address(this), poolA);
        tokenA1.approve(address(pair), poolA);
        tokenB1.mint(address(this), poolB);
        tokenB1.approve(address(pair), poolB);

        if (pair.token0() == address(tokenA1)) {
            liquidityOut = pair.mint(poolA, poolB, address(this));
        } else {
            liquidityOut = pair.mint(poolB, poolA, address(this));
        }
    }

    // Utility function for creating and initializing pairs with poolA:poolB price ratio. Does not use ButtonwoodRouter
    function createAndInitializePair(MockRebasingERC20 tokenA1, MockButtonToken tokenB1, uint256 poolA, uint256 poolB)
        private
        returns (IButtonswapPair pair, uint256 liquidityOut)
    {
        pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA1), address(tokenB1)));
        tokenA1.mint(address(this), poolA);
        tokenA1.approve(address(pair), poolA);

        tokenA1.mint(address(this), poolB);
        tokenA1.approve(address(tokenB1), poolB);
        tokenB1.mint(poolB);
        tokenB1.approve(address(pair), poolB);

        if (pair.token0() == address(tokenA1)) {
            liquidityOut = pair.mint(poolA, poolB, address(this));
        } else {
            liquidityOut = pair.mint(poolB, poolA, address(this));
        }
    }

    // Utility function for creating and initializing ETH-pairs with poolToken:poolETH price ratio. Does not use ButtonwoodRouter
    function createAndInitializePairETH(MockRebasingERC20 token, uint256 poolToken, uint256 poolETH)
        private
        returns (IButtonswapPair pair, uint256 liquidityOut)
    {
        pair = IButtonswapPair(buttonswapFactory.createPair(address(token), address(weth)));
        token.mint(address(this), poolToken);
        token.approve(address(pair), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        weth.approve(address(pair), poolETH);

        if (pair.token0() == address(token)) {
            liquidityOut = pair.mint(poolToken, poolETH, address(this));
        } else {
            liquidityOut = pair.mint(poolETH, poolToken, address(this));
        }
    }

    //    // Utility function for testing functions that use Permit
    //    function generateUserAPermitSignature(IButtonswapPair pair, uint256 liquidity, uint256 deadline)
    //        private
    //        view
    //        returns (uint8 v, bytes32 r, bytes32 s)
    //    {
    //        bytes32 permitDigest = keccak256(
    //            abi.encodePacked(
    //                "\x19\x01",
    //                pair.DOMAIN_SEPARATOR(),
    //                keccak256(
    //                    abi.encode(pair.PERMIT_TYPEHASH(), userA, address(basicButtonswapRouter), liquidity, 0, deadline)
    //                )
    //            )
    //        );
    //        return vm.sign(userAPrivateKey, permitDigest);
    //    }

    // Required function for receiving ETH refunds
    receive() external payable {}

    function setUp() public {
        (feeToSetter, feeToSetterPrivateKey) = makeAddrAndKey("feeToSetter");
        (isCreationRestrictedSetter, isCreationRestrictedSetterPrivateKey) =
            makeAddrAndKey("isCreationRestrictedSetter");
        (isPausedSetter, isPausedSetterPrivateKey) = makeAddrAndKey("isPausedSetter");
        (paramSetter, paramSetterPrivateKey) = makeAddrAndKey("paramSetter");
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        tokenA = new MockRebasingERC20("TokenA", "TKNA", 18);
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);
        buttonTokenA = new MockButtonToken(address(tokenA));
        weth = new MockWeth();
        buttonswapFactory = new ButtonswapFactory(feeToSetter, isCreationRestrictedSetter, isPausedSetter, paramSetter);
        genericButtonswapRouter = new GenericButtonswapRouter(address(buttonswapFactory), address(weth));
    }

    function test_factory() public {
        assertEq(genericButtonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_WETH() public {
        assertEq(genericButtonswapRouter.WETH(), address(weth));
    }

    function test_constructor() public {
        assertEq(genericButtonswapRouter.WETH(), address(weth));
        assertEq(genericButtonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_swapExactTokensForTokens_singleSwapWithInsufficientOutputAmount(
        uint256 poolA,
        uint256 poolB,
        uint256 amountIn
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountIn = bound(amountIn, 1000, 10000);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Estimating how much output a trade would give and making amountOutMin +1 higher
        uint256 amountOutMin = ButtonswapLibrary.getAmountOut(amountIn, poolA, poolB) + 1;

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.SWAP, address(tokenB));

        // Approving the router to take at most amountIn tokenA
        tokenA.mint(address(this), amountIn);
        tokenA.approve(address(genericButtonswapRouter), amountIn);

        // Attempting to do a simple swap
        vm.expectRevert(IGenericButtonswapRouterErrors.InsufficientOutputAmount.selector);
        genericButtonswapRouter.swapExactTokensForTokens(
            address(tokenA), amountIn, amountOutMin, swapSteps, address(this), block.timestamp + 1
        );
    }

    function test_swapExactTokensForTokens_singleSwap(
        uint256 poolA,
        uint256 poolB,
        uint256 amountIn,
        uint256 amountOutMin
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountIn = bound(amountIn, 1000, 10000);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Estimating how much output a trade would give
        uint256 expectedAmountOut = ButtonswapLibrary.getAmountOut(amountIn, poolA, poolB);
        // Making sure that expectedAmountOut is positive
        vm.assume(expectedAmountOut > 0);
        // Ensuring amountOutMin bounded below expectedAmountOut
        amountOutMin = bound(amountOutMin, 0, expectedAmountOut);

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.SWAP, address(tokenB));

        // Approving the router to take at most amountIn tokenA
        tokenA.mint(address(this), amountIn);
        tokenA.approve(address(genericButtonswapRouter), amountIn);

        // Doing a single swap
        uint256[] memory amounts = genericButtonswapRouter.swapExactTokensForTokens(
            address(tokenA), amountIn, amountOutMin, swapSteps, address(this), block.timestamp + 1
        );

        // Validating the correct amounts
        assertEq(amounts[0], amountIn, "First amount should be amountIn");
        assertEq(amounts[1], expectedAmountOut, "Last amount should be expectedAmountOut");
    }

    function test_swapExactTokensForTokens_singleWrapButtonWithInsufficientOutputAmount(
        uint256 poolA,
        uint256 poolbA,
        uint256 amountIn
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolbA = bound(poolbA, 10000, type(uint112).max);

        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountIn = bound(amountIn, 1000, 10000);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, buttonTokenA, poolA, poolbA);

        // Estimating how much output a wrap-button would give and making amountOutMin +1 higher
        uint256 amountOutMin = amountIn + 1;

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.WRAP_BUTTON, address(buttonTokenA));

        // Approving the router to take at most amountIn tokenA
        tokenA.mint(address(this), amountIn);
        tokenA.approve(address(genericButtonswapRouter), amountIn);

        // Attempting to do a simple swap
        vm.expectRevert(IGenericButtonswapRouterErrors.InsufficientOutputAmount.selector);
        genericButtonswapRouter.swapExactTokensForTokens(
            address(tokenA), amountIn, amountOutMin, swapSteps, address(this), block.timestamp + 1
        );
    }

    function test_swapExactTokensForTokens_singleWrapButton(
        uint256 poolA,
        uint256 poolbA,
        uint256 amountIn,
        uint256 amountOutMin
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolbA = bound(poolbA, 10000, type(uint112).max);

        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountIn = bound(amountIn, 1000, 10000);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, buttonTokenA, poolA, poolbA);

        // Estimating how much output a trade would give
        uint256 expectedAmountOut = amountIn;
        // Ensuring amountOutMin bounded below expectedAmountOut
        amountOutMin = bound(amountOutMin, 0, expectedAmountOut);

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.WRAP_BUTTON, address(buttonTokenA));

        // Approving the router to take at most amountIn tokenA
        tokenA.mint(address(this), amountIn);
        tokenA.approve(address(genericButtonswapRouter), amountIn);

        // Doing a single wrap-button
        uint256[] memory amounts = genericButtonswapRouter.swapExactTokensForTokens(
            address(tokenA), amountIn, amountOutMin, swapSteps, address(this), block.timestamp + 1
        );

        // Validating the correct amounts
        assertEq(amounts[0], amountIn, "First amount should be amountIn");
        assertEq(amounts[1], expectedAmountOut, "Last amount should be expectedAmountOut");
    }
}
