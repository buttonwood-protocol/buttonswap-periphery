// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IButtonswapPairErrors} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPairErrors.sol";
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
import {IButtonswapPairErrors} from
    "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPairErrors.sol";
import {MathExtended}  from "../utils/MathExtended.sol";
import {MockERC20} from "buttonswap-periphery_mock-contracts/MockERC20.sol";
import {MockERC20} from "buttonswap-periphery_mock-contracts/MockERC20.sol";
import {console} from "buttonswap-periphery_forge-std/console.sol";

contract GenericButtonswapRouterRemoveLiquidityTest is Test, IGenericButtonswapRouterErrors {
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
    MockRebasingERC20 public tokenC;
    MockButtonToken public buttonTokenA;
    MockButtonToken public buttonTokenB;
    IWETH public weth;
    ButtonswapFactory public buttonswapFactory;
    GenericButtonswapRouter public genericButtonswapRouter;
    IGenericButtonswapRouter.RemoveLiquidityStep public removeLiquidityStep;

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

    // Utility function for creating and initializing button-pairs with poolButtonA:poolB price ratio. Does not use ButtonwoodRouter
    function createAndInitializePairButton(MockRebasingERC20 tokenA1, MockButtonToken buttonTokenB1, uint256 poolA, uint256 poolButtonB)
    private
    returns (IButtonswapPair pair, uint256 liquidityOut)
    {
        pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA1), address(buttonTokenB1)));

        tokenA1.mint(address(this), poolA);
        tokenA1.approve(address(pair), poolA);
        MockRebasingERC20 tokenB1 = MockRebasingERC20(buttonTokenB1.underlying());
        tokenB1.mint(address(this), poolButtonB);
        tokenB1.approve(address(buttonTokenB1), poolButtonB);
        buttonTokenB1.mint(poolButtonB);
        buttonTokenB1.approve(address(pair), poolButtonB);


        if (pair.token0() == address(tokenA1)) {
            liquidityOut = pair.mint(poolA, poolButtonB, address(this));
        } else {
            liquidityOut = pair.mint(poolButtonB, poolA, address(this));
        }
    }

    // Utility function for testing functions that use Permit
    function generateUserPermitSignature(address user, uint256 userPrivateKey, IButtonswapPair pair, uint256 liquidity, uint256 deadline)
        private
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 permitDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                pair.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(pair.PERMIT_TYPEHASH(), user, address(genericButtonswapRouter), liquidity, 0, deadline)
                )
            )
        );
        return vm.sign(userPrivateKey, permitDigest);
    }

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
        tokenC = new MockRebasingERC20("TokenC", "TKNC", 18);
        buttonTokenA = new MockButtonToken(address(tokenA));
        buttonTokenB = new MockButtonToken(address(tokenB));
        weth = new MockWeth();
        buttonswapFactory =
        new ButtonswapFactory(feeToSetter, isCreationRestrictedSetter, isPausedSetter, paramSetter, "Token Name", "SYMBOL");
        genericButtonswapRouter = new GenericButtonswapRouter(address(buttonswapFactory), address(weth));
    }

    function test_removeLiquidity_pairDoesNotExist(address tokenA1, address tokenB1, uint256 liquidity) public {
        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 0, type(uint112).max);

        // Validating pair doesn't exist
        assertEq(buttonswapFactory.getPair(address(tokenA1), address(tokenB1)), address(0), "Pair should not exist");

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA1);
        removeLiquidityStep.tokenB = address(tokenB1);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove liquidity from a non-existent pair
        vm.expectRevert(); // ToDo: Throw PairDoesNotExist error
        genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);
    }

    function test_removeLiquidity_insufficientAmountA(uint256 poolA, uint256 poolB, uint256 liquidity, uint256 amountAMin) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA returned from removing liquidity
        uint256 amountA = (poolA * liquidity) / pair.totalSupply();
        // Guaranteeing that the amountAMin is greater than the amountA returned
        vm.assume(amountAMin > amountA);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = amountAMin;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove liquidity
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector, address(tokenA), amountA, amountAMin
            )
        );
        genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);
    }

    function test_removeLiquidity_insufficientAmountB(uint256 poolA, uint256 poolB, uint256 liquidity, uint256 amountBMin) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountB returned from removing liquidity
        uint256 amountB = (poolB * liquidity) / pair.totalSupply();
        // Guaranteeing that the amountAMin is greater than the amountA returned
        vm.assume(amountBMin > amountB);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = amountBMin;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove liquidity
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector, address(tokenB), amountB, amountBMin
            )
        );
        genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);
    }

    function test_removeLiquidity_noHops(uint256 poolA, uint256 poolB, uint256 liquidity) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        uint256 expectedAmountA = (poolA * liquidity) / pair.totalSupply();
        uint256 expectedAmountB = (poolB * liquidity) / pair.totalSupply();

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    function test_removeLiquidity_noHopsWithReservoir(uint256 poolA, uint256 poolB, uint256 liquidity, uint8 rebaseNumerator, uint8 rebaseDenominator, bool aOrB) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);

        // Rebasing token up positively up to create a reservoir and ensuring there's no overflow
        if (aOrB) {
            vm.assume(poolA < (type(uint112).max / rebaseNumerator) * rebaseDenominator);
            tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);
        } else {
            vm.assume(poolB < (type(uint112).max / rebaseNumerator) * rebaseDenominator);
            tokenB.applyMultiplier(rebaseNumerator, rebaseDenominator);
        }

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        uint256 expectedAmountA = (tokenA.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        uint256 expectedAmountB = (tokenB.balanceOf(address(pair)) * liquidity) / pair.totalSupply();

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    // Removing liquidity from a A-B pair and swapping A->C
    function test_removeLiquidity_singleSwapA(
        uint256 poolA,
        uint256 poolB,
        uint256 poolAC,
        uint256 poolC,
        uint256 liquidity
    ) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Creating A-C pair with at least minimum liquidity and poolAC:poolC price ratio
        poolAC = bound(poolAC, 10000, type(uint112).max);
        poolC = bound(poolC, 10000, type(uint112).max);
        createAndInitializePair(tokenA, tokenC, poolAC, poolC);

        // Bound liquidity to be within the range of any pair's liquidity`
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA intermediate step from removing liquidity
        uint256 expectedAmountA = (tokenA.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        // Ensuring expectedAmountA is within poolAC bounds
        vm.assume(expectedAmountA > 0);
        vm.assume(expectedAmountA < type(uint112).max - poolAC);
        // Estimating amountC returned from swapping A->C
        uint256 expectedAmountC =
            ButtonswapLibrary.getAmountOut(
                expectedAmountA,
                poolAC,
                poolC
            );
        // Ensuring expectedAmountC is within poolC bounds
        vm.assume(expectedAmountC > 0);
        vm.assume(expectedAmountC < poolC);
        // Estimating amountB returned from removing liquidity
        uint256 expectedAmountB = (tokenB.balanceOf(address(pair)) * liquidity) / pair.totalSupply();

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
        removeLiquidityStep.swapStepsA.push();
        removeLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.SWAP;
        removeLiquidityStep.swapStepsA[0].tokenOut = address(tokenC);
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountsA/amountsB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsA[1], expectedAmountC, "AmountsA[1] should equal expectedAmountC");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    // Removing liquidity from a A-B pair and swapping B->C
    function test_removeLiquidity_singleSwapB(
        uint256 poolA,
        uint256 poolB,
        uint256 poolBC,
        uint256 poolC,
        uint256 liquidity
    ) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Creating B-C pair with at least minimum liquidity and poolBC:poolC price ratio
        poolBC = bound(poolBC, 10000, type(uint112).max);
        poolC = bound(poolC, 10000, type(uint112).max);
        createAndInitializePair(tokenB, tokenC, poolBC, poolC);

        // Bound liquidity to be within the range of any pair's liquidity`
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA returned from removing liquidity
        uint256 expectedAmountA = (tokenA.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        // Estimating amountB intermediate step from removing liquidity
        uint256 expectedAmountB = (tokenB.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        // Ensuring expectedAmountB is within poolBC bounds
        vm.assume(expectedAmountB > 0);
        vm.assume(expectedAmountB < type(uint112).max - poolBC);
        // Estimating amountC returned from swapping A->C
        uint256 expectedAmountC =
                            ButtonswapLibrary.getAmountOut(
                expectedAmountB,
                poolBC,
                poolC
            );
        // Ensuring expectedAmountC is within poolC bounds
        vm.assume(expectedAmountC > 0);
        vm.assume(expectedAmountC < poolC);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
        removeLiquidityStep.swapStepsB.push();
        removeLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.SWAP;
        removeLiquidityStep.swapStepsB[0].tokenOut = address(tokenC);
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountsA/amountsB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
        assertEq(amountsB[1], expectedAmountC, "AmountsB[1] should equal expectedAmountC");
    }

    // Removing liquidity from a A-B pair and button-wrapping A->bA
    function test_removeLiquidity_singleWrapButtonA(
        uint256 poolA,
        uint256 poolB,
        uint256 liquidity
    ) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Bound liquidity to be within the range of any pair's liquidity`
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA intermediate step from removing liquidity
        uint256 expectedAmountA = (tokenA.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        uint256 expectedAmountButtonA = buttonTokenA.underlyingToWrapper(expectedAmountA);
        uint256 expectedAmountB = (tokenB.balanceOf(address(pair)) * liquidity) / pair.totalSupply();

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
        removeLiquidityStep.swapStepsA.push();
        removeLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.WRAP_BUTTON;
        removeLiquidityStep.swapStepsA[0].tokenOut = address(buttonTokenA);
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountsA/amountsB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsA[1], expectedAmountButtonA, "AmountsA[1] should equal expectedAmountButtonA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    // Removing liquidity from a A-B pair and button-wrapping A->bB
    function test_removeLiquidity_singleWrapButtonB(
        uint256 poolA,
        uint256 poolB,
        uint256 liquidity
    ) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Bound liquidity to be within the range of any pair's liquidity`
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA intermediate step from removing liquidity
        uint256 expectedAmountA = (tokenA.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        uint256 expectedAmountB = (tokenB.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        uint256 expectedAmountButtonB = buttonTokenB.underlyingToWrapper(expectedAmountB);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
        removeLiquidityStep.swapStepsB.push();
        removeLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.WRAP_BUTTON;
        removeLiquidityStep.swapStepsB[0].tokenOut = address(buttonTokenB);
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountsA/amountsB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
        assertEq(amountsB[1], expectedAmountButtonB, "AmountsB[1] should equal expectedAmountButtonB");
    }

    // Removing liquidity from a bA-B pair and button-wrapping bA->A
    function test_removeLiquidity_singleUnwrapButtonA(
        uint256 poolButtonA,
        uint256 poolB,
        uint256 liquidity
    ) public {
        // Creating bA-B pair with at least minimum liquidity and poolButtonA:poolB price ratio
        poolButtonA = bound(poolButtonA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairButton(tokenB, buttonTokenA, poolB, poolButtonA);

        // Bound liquidity to be within the range of any pair's liquidity`
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountButtonA intermediate step from removing liquidity
        uint256 expectedAmountButtonA = (buttonTokenA.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        // Estimating amountA returned from unwrapping bA->A
        uint256 expectedAmountA = buttonTokenA.wrapperToUnderlying(expectedAmountButtonA);
        // Estimating amountB returned from removing liquidity
        uint256 expectedAmountB = (tokenB.balanceOf(address(pair)) * liquidity) / pair.totalSupply();

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(buttonTokenA);
        removeLiquidityStep.tokenB = address(tokenB);
        removeLiquidityStep.swapStepsA.push();
        removeLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.UNWRAP_BUTTON;
        removeLiquidityStep.swapStepsA[0].tokenOut = address(tokenA);
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountsA/amountsB returned
        assertEq(amountsA[0], expectedAmountButtonA, "AmountsA[0] should equal expectedAmountButtonA");
        assertEq(amountsA[1], expectedAmountA, "AmountsA[1] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    // Removing liquidity from a A-Bb pair and button-wrapping bB->B
    function test_removeLiquidity_singleUnwrapButtonB(
        uint256 poolA,
        uint256 poolButtonB,
        uint256 liquidity
    ) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolButtonB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolButtonB = bound(poolButtonB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairButton(tokenA, buttonTokenB, poolA, poolButtonB);

        // Bound liquidity to be within the range of any pair's liquidity`
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA returned from removing liquidity
        uint256 expectedAmountA = (tokenA.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        // Estimating amountButtonB intermediate step from removing liquidity
        uint256 expectedAmountButtonB = (buttonTokenB.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        // Estimating amountB returned from unwrapping bB->B
        uint256 expectedAmountB = buttonTokenB.wrapperToUnderlying(expectedAmountButtonB);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(buttonTokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
        removeLiquidityStep.swapStepsB.push();
        removeLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.UNWRAP_BUTTON;
        removeLiquidityStep.swapStepsB[0].tokenOut = address(tokenB);
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountsA/amountsB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountButtonB, "AmountsB[0] should equal expectedAmountButtonB");
        assertEq(amountsB[1], expectedAmountB, "AmountsB[1] should equal expectedAmountB");
    }

    // test_removeLiquidity_singleWrapWeth not a viable test-cases since pairs can't accept raw-ETH

    // Removing liquidity from a WETH-B pair and weth-unwrapping WETH->ETH
    function test_removeLiquidity_singleUnwrapWethA(
        uint256 poolWETH,
        uint256 poolB,
        uint256 liquidity
    ) public {
        // Creating WETH-B pair with at least minimum liquidity and poolWETH:poolB price ratio
        poolWETH = bound(poolWETH, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenB, poolB, poolWETH);

        // Bound liquidity to be within the range of any pair's liquidity`
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountWETH intermediate step from removing liquidity
        uint256 expectedAmountWETH = (weth.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        // Estimating amountB returned from removing liquidity
        uint256 expectedAmountB = (tokenB.balanceOf(address(pair)) * liquidity) / pair.totalSupply();

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(weth);
        removeLiquidityStep.tokenB = address(tokenB);
        removeLiquidityStep.swapStepsA.push();
        removeLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.UNWRAP_WETH;
        removeLiquidityStep.swapStepsA[0].tokenOut = address(0);
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountsA/amountsB returned
        assertEq(amountsA[0], expectedAmountWETH, "AmountsA[0] should equal expectedAmountWETH");
        assertEq(amountsA[1], expectedAmountWETH, "AmountsA[1] should also equal expectedAmountWETH");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    // Removing liquidity from a A-WETH pair and weth-unwrapping WETH->ETH
    function test_removeLiquidity_singleUnwrapWethB(
        uint256 poolA,
        uint256 poolWETH,
        uint256 liquidity
    ) public {
        // Creating A-WETH pair with at least minimum liquidity and poolA:poolWETH price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolWETH = bound(poolWETH, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenA, poolA, poolWETH);

        // Bound liquidity to be within the range of any pair's liquidity`
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA returned from removing liquidity
        uint256 expectedAmountA = (tokenA.balanceOf(address(pair)) * liquidity) / pair.totalSupply();
        // Estimating amountWETH intermediate step from removing liquidity
        uint256 expectedAmountWETH = (weth.balanceOf(address(pair)) * liquidity) / pair.totalSupply();

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(weth);
//        removeLiquidityStep.swapStepsA; // Default to []
        removeLiquidityStep.swapStepsB.push();
        removeLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.UNWRAP_WETH;
        removeLiquidityStep.swapStepsB[0].tokenOut = address(0);
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountsA/amountsB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountWETH, "AmountsB[0] should equal expectedAmountWETH");
        assertEq(amountsB[1], expectedAmountWETH, "AmountsB[1] should also equal expectedAmountWETH");
    }


    function test_removeLiquidityFromReservoir_pairDoesNotExist(address tokenA1, address tokenB1, uint256 liquidity) public {
        // Validating pair doesn't exist
        assertEq(buttonswapFactory.getPair(address(tokenA1), address(tokenB1)), address(0), "Pair should not exist");

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA1);
        removeLiquidityStep.tokenB = address(tokenB1);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove liquidity from a non-existent pair
        vm.expectRevert(); // ToDo: Throw PairDoesNotExist error
        genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);
    }

    function test_removeLiquidityFromReservoir_noReservoir(uint256 poolA, uint256 poolB) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidityOut);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidityOut;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove all the liquidity from a pair with no reservoir
        vm.expectRevert(abi.encodeWithSelector(IButtonswapPairErrors.InsufficientReservoir.selector));
        genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);
    }

    function test_removeLiquidityFromReservoir_reservoirAInsufficientTokenAmount(uint256 poolA, uint256 poolB, uint256 liquidity, uint8 rebaseNumerator, uint8 rebaseDenominator, bool insufficientAOrB) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);

        // Rebasing tokenA up to create a reservoir and ensuring there's no overflow
        vm.assume(poolA < (type(uint112).max / rebaseNumerator) * rebaseDenominator);
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Estimating reservoirA size
        uint256 reservoirA = (poolA * rebaseNumerator) / rebaseDenominator - poolA;

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        (uint256 tokenOutA, uint256 swappedReservoirAmountA) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(tokenA), address(tokenB), liquidity);
        // Ensuring that that swappedReservoirAmountA is less than the reservoir
        vm.assume(swappedReservoirAmountA < reservoirA);
        // Ensuring that swappedReservoirAmountA is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountA < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutA is non-zero
        vm.assume(tokenOutA > 0);
        // Ensuring that tokenOutA is less than the reservoir
        vm.assume(tokenOutA < reservoirA);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        // Ensuring insufficient token output
        if (insufficientAOrB) {
            removeLiquidityStep.amountAMin = tokenOutA + 1;
            removeLiquidityStep.amountBMin = 0;
        } else {
            removeLiquidityStep.amountAMin = 0;
            removeLiquidityStep.amountBMin = 1;
        }
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to removing liquidity with insufficient amount
        if (insufficientAOrB) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector, address(tokenA), tokenOutA, tokenOutA + 1
                )
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector, address(tokenB), 0, 1
                )
            );
        }
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);
    }

    function test_removeLiquidityFromReservoir_reservoirBInsufficientTokenAmount(uint256 poolA, uint256 poolB, uint256 liquidity, uint8 rebaseNumerator, uint8 rebaseDenominator, bool insufficientAOrB) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);

        // Rebasing tokenB up to create a reservoir and ensuring there's no overflow
        vm.assume(poolB < (type(uint112).max / rebaseNumerator) * rebaseDenominator);
        tokenB.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Estimating reservoirB size
        uint256 reservoirB = (poolB * rebaseNumerator) / rebaseDenominator - poolB;

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        (uint256 tokenOutB, uint256 swappedReservoirAmountB) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(tokenB), address(tokenA), liquidity);
        // Ensuring that that swappedReservoirAmountB is less than the reservoir
        vm.assume(swappedReservoirAmountB < reservoirB);
        // Ensuring that swappedReservoirAmountB is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountB < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutB is non-zero
        vm.assume(tokenOutB > 0);
        // Ensuring that tokenOutB is less than the reservoir
        vm.assume(tokenOutB < reservoirB);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        // Ensuring insufficient token output
        if (insufficientAOrB) {
            removeLiquidityStep.amountAMin = 1;
            removeLiquidityStep.amountBMin = 0;
        } else {
            removeLiquidityStep.amountAMin = 0;
            removeLiquidityStep.amountBMin = tokenOutB + 1;
        }
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to removing liquidity with insufficient amount
        if (insufficientAOrB) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector, address(tokenA), 0, 1
                )
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector, address(tokenB), tokenOutB, tokenOutB + 1
                )
            );
        }
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);
    }

    function test_removeLiquidityFromReservoir_reservoirANoHops(uint256 poolA, uint256 poolB, uint256 liquidity, uint8 rebaseNumerator, uint8 rebaseDenominator) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);

        // Rebasing tokenA up to create a reservoir and ensuring there's no overflow
        vm.assume(poolA < (type(uint112).max / rebaseNumerator) * rebaseDenominator);
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Estimating reservoirA size
        uint256 reservoirA = (poolA * rebaseNumerator) / rebaseDenominator - poolA;

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        (uint256 tokenOutA, uint256 swappedReservoirAmountA) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(tokenA), address(tokenB), liquidity);
        // Ensuring that that swappedReservoirAmountA is less than the reservoir
        vm.assume(swappedReservoirAmountA < reservoirA);
        // Ensuring that swappedReservoirAmountA is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountA < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutA is non-zero
        vm.assume(tokenOutA > 0);
        // Ensuring that tokenOutA is less than the reservoir
        vm.assume(tokenOutA < reservoirA);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], tokenOutA, "AmountsA[0] should equal tokenOutA");
        assertEq(amountsB.length, 0, "AmountsB should be empty");
    }

    function test_removeLiquidityFromReservoir_reservoirBNoHops(uint256 poolA, uint256 poolB, uint256 liquidity, uint8 rebaseNumerator, uint8 rebaseDenominator) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);

        // Rebasing tokenB up to create a reservoir and ensuring there's no overflow
        vm.assume(poolB < (type(uint112).max / rebaseNumerator) * rebaseDenominator);
        tokenB.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Estimating reservoirB size
        uint256 reservoirB = (poolB * rebaseNumerator) / rebaseDenominator - poolB;

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        (uint256 tokenOutB, uint256 swappedReservoirAmountB) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(tokenB), address(tokenA), liquidity);
        // Ensuring that that swappedReservoirAmountB is less than the reservoir
        vm.assume(swappedReservoirAmountB < reservoirB);
        // Ensuring that swappedReservoirAmountB is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountB < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutB is non-zero
        vm.assume(tokenOutB > 0);
        // Ensuring that tokenOutB is less than the reservoir
        vm.assume(tokenOutB < reservoirB);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA.length, 0, "AmountsA should be empty");
        assertEq(amountsB[0], tokenOutB, "AmountsB[0] should equal tokenOutB");
    }

    // Removing liquidity from A-reservoir in an A-B pair and swapping A->C
    function test_removeLiquidityFromReservoir_singleSwapA(uint256 poolA, uint256 poolB, uint256 reservoirA, uint256 poolAC, uint256 poolC, uint256 liquidity) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max - 1);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Creating an artificial reservoir by donating tokenA to the pair
        reservoirA = bound(reservoirA, 1, type(uint112).max - poolA);
        tokenA.mint(address(pair), reservoirA);

        // Creating A-C pair with at least minimum liquidity and poolAC:poolC price ratio
        poolAC = bound(poolAC, 10000, type(uint112).max);
        poolC = bound(poolC, 10000, type(uint112).max);
        createAndInitializePair(tokenA, tokenC, poolAC, poolC);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        (uint256 tokenOutA, uint256 swappedReservoirAmountA) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(tokenA), address(tokenB), liquidity);
        // Ensuring that that swappedReservoirAmountA is less than the reservoir
        vm.assume(swappedReservoirAmountA < reservoirA);
        // Ensuring that swappedReservoirAmountA is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountA < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutA is non-zero
        vm.assume(tokenOutA > 0);
        // Ensuring that tokenOutA is less than the reservoir
        vm.assume(tokenOutA < reservoirA);
        // Ensuring tokenOutA + poolAC doesn't overflow
        vm.assume(tokenOutA < type(uint112).max - poolAC);

        // Estimating amountC from swapping A->C and ensuring no errors
        uint256 expectedAmountC = ButtonswapLibrary.getAmountOut(tokenOutA, poolAC, poolC);
        vm.assume(expectedAmountC > 0);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
        removeLiquidityStep.swapStepsA.push();
        removeLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.SWAP;
        removeLiquidityStep.swapStepsA[0].tokenOut = address(tokenC);
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], tokenOutA, "AmountsA[0] should equal tokenOutA");
        assertEq(amountsA[1], expectedAmountC, "AmountsA[1] should equal expectedAmountC");
        assertEq(amountsB.length, 0, "AmountsB should be empty");
    }

    // Removing liquidity from B-reservoir in an A-B pair and swapping B->C
    function test_removeLiquidityFromReservoir_singleSwapB(uint256 poolA, uint256 poolB, uint256 reservoirB, uint256 poolBC, uint256 poolC, uint256 liquidity) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max - 1);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Creating an artificial reservoir by donating tokenB to the pair
        reservoirB = bound(reservoirB, 1, type(uint112).max - poolB);
        tokenB.mint(address(pair), reservoirB);

        // Creating B-C pair with at least minimum liquidity and poolBC:poolC price ratio
        poolBC = bound(poolBC, 10000, type(uint112).max);
        poolC = bound(poolC, 10000, type(uint112).max);
        createAndInitializePair(tokenB, tokenC, poolBC, poolC);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        (uint256 tokenOutB, uint256 swappedReservoirAmountB) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(tokenB), address(tokenA), liquidity);
        // Ensuring that that swappedReservoirAmountB is less than the reservoir
        vm.assume(swappedReservoirAmountB < reservoirB);
        // Ensuring that swappedReservoirAmountB is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountB < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutB is non-zero
        vm.assume(tokenOutB > 0);
        // Ensuring that tokenOutB is less than the reservoir
        vm.assume(tokenOutB < reservoirB);
        // Ensuring tokenOutB + poolBC doesn't overflow
        vm.assume(tokenOutB < type(uint112).max - poolBC);

        // Estimating amountC from swapping B->C and ensuring no errors
        uint256 expectedAmountC = ButtonswapLibrary.getAmountOut(tokenOutB, poolBC, poolC);
        vm.assume(expectedAmountC > 0);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
        removeLiquidityStep.swapStepsB.push();
        removeLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.SWAP;
        removeLiquidityStep.swapStepsB[0].tokenOut = address(tokenC);
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA.length, 0, "AmountsA should be empty");
        assertEq(amountsB[0], tokenOutB, "AmountsB[0] should equal tokenOutB");
        assertEq(amountsB[1], expectedAmountC, "AmountsB[1] should equal expectedAmountC");
    }

    // Removing liquidity from A-reservoir in an A-B pair and button-wrapping A->bA
    function test_removeLiquidityFromReservoir_singleWrapButtonA(uint256 poolA, uint256 poolB, uint256 reservoirA, uint256 liquidity) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max - 1);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Creating an artificial reservoir by donating tokenA to the pair
        reservoirA = bound(reservoirA, 1, type(uint112).max - poolA);
        tokenA.mint(address(pair), reservoirA);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        (uint256 tokenOutA, uint256 swappedReservoirAmountA) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(tokenA), address(tokenB), liquidity);
        // Ensuring that that swappedReservoirAmountA is less than the reservoir
        vm.assume(swappedReservoirAmountA < reservoirA);
        // Ensuring that swappedReservoirAmountA is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountA < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutA is non-zero
        vm.assume(tokenOutA > 0);
        // Ensuring that tokenOutA is less than the reservoir
        vm.assume(tokenOutA < reservoirA);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
        removeLiquidityStep.swapStepsA.push();
        removeLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.WRAP_BUTTON;
        removeLiquidityStep.swapStepsA[0].tokenOut = address(buttonTokenA);
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], tokenOutA, "AmountsA[0] should equal tokenOutA");
        assertEq(amountsA[1], buttonTokenA.underlyingToWrapper(tokenOutA), "AmountsA[1] should equal tokenOutA converted to buttonTokenA");
        assertEq(amountsB.length, 0, "AmountsB should be empty");
    }

    // Removing liquidity from B-reservoir in an A-B pair and button-wrapping B->bB
    function test_removeLiquidityFromReservoir_singleWrapButtonB(uint256 poolA, uint256 poolB, uint256 reservoirB, uint256 liquidity) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max - 1);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Creating an artificial reservoir by donating tokenB to the pair
        reservoirB = bound(reservoirB, 1, type(uint112).max - poolB);
        tokenB.mint(address(pair), reservoirB);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        (uint256 tokenOutB, uint256 swappedReservoirAmountB) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(tokenB), address(tokenA), liquidity);
        // Ensuring that that swappedReservoirAmountB is less than the reservoir
        vm.assume(swappedReservoirAmountB < reservoirB);
        // Ensuring that swappedReservoirAmountB is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountB < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutB is non-zero
        vm.assume(tokenOutB > 0);
        // Ensuring that tokenOutB is less than the reservoir
        vm.assume(tokenOutB < reservoirB);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
        removeLiquidityStep.swapStepsB.push();
        removeLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.WRAP_BUTTON;
        removeLiquidityStep.swapStepsB[0].tokenOut = address(buttonTokenB);
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA.length, 0, "AmountsA should be empty");
        assertEq(amountsB[0], tokenOutB, "AmountsB[0] should equal tokenOutB");
        assertEq(amountsB[1], buttonTokenB.underlyingToWrapper(tokenOutB), "AmountsB[1] should equal tokenOutB converted to buttonTokenB");
    }

    // Removing liquidity from A-reservoir in a bA-B pair and button-wrapping bA->A
    function test_removeLiquidityFromReservoir_singleUnwrapButtonA(uint256 poolButtonA, uint256 poolB, uint256 reservoirButtonA, uint256 liquidity) public {
        // Creating bA-B pair with at least minimum liquidity and poolButtonA:poolB price ratio
        poolButtonA = bound(poolButtonA, 10000, type(uint112).max - 1);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairButton(tokenB, buttonTokenA, poolB, poolButtonA);

        // Creating an artificial reservoir by donating buttonTokenA to the pair
        reservoirButtonA = bound(reservoirButtonA, 1, type(uint112).max - poolButtonA);
        tokenA.mint(address(this), buttonTokenA.wrapperToUnderlying(reservoirButtonA));
        tokenA.approve(address(buttonTokenA), buttonTokenA.wrapperToUnderlying(reservoirButtonA));
        buttonTokenA.mint(reservoirButtonA);
        buttonTokenA.transfer(address(pair), reservoirButtonA);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountButtonA/amountB returned from removing liquidity
        (uint256 tokenOutButtonA, uint256 swappedReservoirAmountButtonA) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(buttonTokenA), address(tokenB), liquidity);
        // Ensuring that that swappedReservoirAmountButtonA is less than the reservoir
        vm.assume(swappedReservoirAmountButtonA < reservoirButtonA);
        // Ensuring that swappedReservoirAmountButtonA is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountButtonA < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutButtonA is non-zero
        vm.assume(tokenOutButtonA > 0);
        // Ensuring that tokenOutButtonA is less than the reservoir
        vm.assume(tokenOutButtonA < reservoirButtonA);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(buttonTokenA);
        removeLiquidityStep.tokenB = address(tokenB);
        removeLiquidityStep.swapStepsA.push();
        removeLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.UNWRAP_BUTTON;
        removeLiquidityStep.swapStepsA[0].tokenOut = address(tokenA);
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], tokenOutButtonA, "AmountsA[0] should equal tokenOutButtonA");
        assertEq(amountsA[1], buttonTokenA.wrapperToUnderlying(tokenOutButtonA), "AmountsA[1] should equal tokenOutButtonA converted to tokenA");
        assertEq(amountsB.length, 0, "AmountsB should be empty");
    }

    // Removing liquidity from B-reservoir in a A-Bb pair and button-wrapping bB->B
    function test_removeLiquidityFromReservoir_singleUnwrapButtonB(uint256 poolA, uint256 poolButtonB, uint256 reservoirButtonB, uint256 liquidity) public {
        // Creating A-bB pair with at least minimum liquidity and poolA:poolButtonB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolButtonB = bound(poolButtonB, 10000, type(uint112).max - 1);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairButton(tokenA, buttonTokenB, poolA, poolButtonB);

        // Creating an artificial reservoir by donating buttonTokenB to the pair
        reservoirButtonB = bound(reservoirButtonB, 1, type(uint112).max - poolButtonB);
        tokenB.mint(address(this), buttonTokenB.wrapperToUnderlying(reservoirButtonB));
        tokenB.approve(address(buttonTokenB), buttonTokenB.wrapperToUnderlying(reservoirButtonB));
        buttonTokenB.mint(reservoirButtonB);
        buttonTokenB.transfer(address(pair), reservoirButtonB);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountButtonA/amountB returned from removing liquidity
        (uint256 tokenOutButtonB, uint256 swappedReservoirAmountButtonB) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(buttonTokenB), address(tokenA), liquidity);
        // Ensuring that that swappedReservoirAmountButtonB is less than the reservoir
        vm.assume(swappedReservoirAmountButtonB < reservoirButtonB);
        // Ensuring that swappedReservoirAmountButtonB is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountButtonB < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutButtonB is non-zero
        vm.assume(tokenOutButtonB > 0);
        // Ensuring that tokenOutButtonB is less than the reservoir
        vm.assume(tokenOutButtonB < reservoirButtonB);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(buttonTokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
        removeLiquidityStep.swapStepsB.push();
        removeLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.UNWRAP_BUTTON;
        removeLiquidityStep.swapStepsB[0].tokenOut = address(tokenB);
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA.length, 0, "AmountsB should be empty");
        assertEq(amountsB[0], tokenOutButtonB, "AmountsA[0] should equal tokenOutButtonB");
        assertEq(amountsB[1], buttonTokenB.wrapperToUnderlying(tokenOutButtonB), "AmountsB[1] should equal tokenOutButtonB converted to tokenB");
    }

    // test_removeLiquidityFromReservoir_singleWrapWeth not a viable test-cases since pairs can't accept raw-ETH

    // Removing liquidity from A-reservoir in a WETH-B pair and weth-unwrapping WETH->ETH
    function test_removeLiquidityFromReservoir_singleUnwrapWethA(uint256 poolWETH, uint256 poolB, uint256 reservoirWETH, uint256 liquidity) public {
        // Creating WETH-B pair with at least minimum liquidity and poolWETH:poolB price ratio
        poolWETH = bound(poolWETH, 10000, type(uint112).max - 1);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenB, poolB, poolWETH);

        // Creating an artificial reservoir by donating WETH to the pair
        reservoirWETH = bound(reservoirWETH, 1, type(uint112).max - poolWETH);
        vm.deal(address(this), reservoirWETH);
        weth.deposit{value: reservoirWETH}();
        weth.transfer(address(pair), reservoirWETH);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountButtonA/amountB returned from removing liquidity
        (uint256 tokenOutWETH, uint256 swappedReservoirAmountWETH) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(weth), address(tokenB), liquidity);
        // Ensuring that that swappedReservoirAmountWETH is less than the reservoir
        vm.assume(swappedReservoirAmountWETH < reservoirWETH);
        // Ensuring that swappedReservoirAmountWETH is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountWETH < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutWETH is non-zero
        vm.assume(tokenOutWETH > 0);
        // Ensuring that tokenOutWETH is less than the reservoir
        vm.assume(tokenOutWETH < reservoirWETH);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(weth);
        removeLiquidityStep.tokenB = address(tokenB);
        removeLiquidityStep.swapStepsA.push();
        removeLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.UNWRAP_WETH;
        removeLiquidityStep.swapStepsA[0].tokenOut = address(0);
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], tokenOutWETH, "AmountsA[0] should equal tokenOutWETH in WETH");
        assertEq(amountsA[1], tokenOutWETH, "AmountsA[1] should equal tokenOutWETH in ETH");
        assertEq(amountsB.length, 0, "AmountsB should be empty");
    }

//    // Removing liquidity from B-reservoir in a A-WETH pair and weth-unwrapping WETH->ETH
    function test_removeLiquidityFromReservoir_singleUnwrapWethB(uint256 poolA, uint256 poolWETH, uint256 reservoirWETH, uint256 liquidity) public {
        // Creating A-WETH pair with at least minimum liquidity and poolA:poolWETH price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolWETH = bound(poolWETH, 10000, type(uint112).max - 1);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenA, poolA, poolWETH);

        // Creating an artificial reservoir by donating WETH to the pair
        reservoirWETH = bound(reservoirWETH, 1, type(uint112).max - poolWETH);
        vm.deal(address(this), reservoirWETH);
        weth.deposit{value: reservoirWETH}();
        weth.transfer(address(pair), reservoirWETH);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountButtonA/amountB returned from removing liquidity
        (uint256 tokenOutWETH, uint256 swappedReservoirAmountWETH) = ButtonswapLibrary.getBurnSwappedAmounts(address(buttonswapFactory), address(weth), address(tokenA), liquidity);
        // Ensuring that that swappedReservoirAmountWETH is less than the reservoir
        vm.assume(swappedReservoirAmountWETH < reservoirWETH);
        // Ensuring that swappedReservoirAmountWETH is less than swappableReservoirLimit
        vm.assume(swappedReservoirAmountWETH < pair.getSwappableReservoirLimit());
        // Ensuring that tokenOutWETH is non-zero
        vm.assume(tokenOutWETH > 0);
        // Ensuring that tokenOutWETH is less than the reservoir
        vm.assume(tokenOutWETH < reservoirWETH);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY_WITH_RESERVOIR;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(weth);
//        removeLiquidityStep.swapStepsA; // Default to []
        removeLiquidityStep.swapStepsB.push();
        removeLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.UNWRAP_WETH;
        removeLiquidityStep.swapStepsB[0].tokenOut = address(0);
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidity(removeLiquidityStep, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA.length, 0, "amountsA should be empty");
        assertEq(amountsB[0], tokenOutWETH, "amountsB[0] should equal tokenOutWETH in WETH");
        assertEq(amountsB[1], tokenOutWETH, "amountsB[1] should equal tokenOutWETH in ETH");
    }

    function test_removeLiquidityWithPermit_specificPermission(uint256 poolA, uint256 poolB, uint256 liquidity) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Transferring pair liquidity to userA to test out the permit functionality
        pair.transfer(userA, liquidityOut);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        uint256 expectedAmountA = (poolA * liquidity) / pair.totalSupply();
        uint256 expectedAmountB = (poolB * liquidity) / pair.totalSupply();

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserPermitSignature(userA, userAPrivateKey, pair, liquidity, deadline);

        // Removing liquidity as userA
        vm.prank(userA);
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidityWithPermit(
            removeLiquidityStep,
            to,
            deadline,
            false,
            v,
            r,
            s
        );

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    function test_removeLiquidityWithPermit_MaxPermission(uint256 poolA, uint256 poolB, uint256 liquidity) public {
        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Transferring pair liquidity to userA to test out the permit functionality
        pair.transfer(userA, liquidityOut);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        uint256 expectedAmountA = (poolA * liquidity) / pair.totalSupply();
        uint256 expectedAmountB = (poolB * liquidity) / pair.totalSupply();

        // Creating the removeLiquidityStep
        removeLiquidityStep.operation = ButtonswapOperations.RemoveLiquidity.REMOVE_LIQUIDITY;
        removeLiquidityStep.tokenA = address(tokenA);
        removeLiquidityStep.tokenB = address(tokenB);
//        removeLiquidityStep.swapStepsA; // Default to []
//        removeLiquidityStep.swapStepsB; // Default to []
        removeLiquidityStep.liquidity = liquidity;
        removeLiquidityStep.amountAMin = 0;
        removeLiquidityStep.amountBMin = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserPermitSignature(userA, userAPrivateKey, pair, type(uint256).max, deadline);

        // Removing liquidity as userA
        vm.prank(userA);
        (uint256[] memory amountsA, uint256[] memory amountsB) = genericButtonswapRouter.removeLiquidityWithPermit(
            removeLiquidityStep,
            to,
            deadline,
            true,
            v,
            r,
            s
        );

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }
}
