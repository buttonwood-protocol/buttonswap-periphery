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
import {IButtonswapPairErrors} from
    "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPairErrors.sol";
import {MathExtended}  from "../utils/MathExtended.sol";
import {MockERC20} from "buttonswap-periphery_mock-contracts/MockERC20.sol";
import {MockERC20} from "buttonswap-periphery_mock-contracts/MockERC20.sol";
import {console} from "buttonswap-periphery_forge-std/console.sol";

contract GenericButtonswapRouterAddLiquidityTest is Test, IGenericButtonswapRouterErrors {
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
    IGenericButtonswapRouter.AddLiquidityStep public addLiquidityStep;

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
        tokenC = new MockRebasingERC20("TokenC", "TKNC", 18);
        buttonTokenA = new MockButtonToken(address(tokenA));
        buttonTokenB = new MockButtonToken(address(tokenB));
        weth = new MockWeth();
        buttonswapFactory =
        new ButtonswapFactory(feeToSetter, isCreationRestrictedSetter, isPausedSetter, paramSetter, "Token Name", "SYMBOL");
        genericButtonswapRouter = new GenericButtonswapRouter(address(buttonswapFactory), address(weth));
    }

    function test_addLiquidity_createPairNoHops(uint256 amountADesired, uint256 amountBDesired) public {
        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
//        addLiquidityStep.swapStepsA; // Default to []
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(buttonswapFactory.getPair(address(tokenA), address(tokenB)), address(0), "Pair should not exist yet");

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        // Validating state
        address pairAddress = buttonswapFactory.getPair(address(tokenA), address(tokenB));
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be equal to amountADesired");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be equal to amountBDesired");
        assertEq(liquidity, MathExtended.sqrt(amountADesired * amountBDesired) - 1000, "Liquidity should be equal geometric mean - 1000");
    }

    // Swapping A->C, then adding liquidity C+B
    function test_addLiquidity_createPairSingleSwapA(uint256 poolA, uint256 poolC, uint256 amountADesired, uint256 amountBDesired) public {
        // Creating an existing pair for the swap
        poolA = bound(poolA, 10000, type(uint112).max);
        poolC = bound(poolC, 10000, type(uint112).max);
        createAndInitializePair(tokenA, tokenC, poolA, poolC);

        // Minting enough for minimum liquidity requirement and not too much to mess up the A->C swap
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        vm.assume(amountADesired < poolA);
        vm.assume(ButtonswapLibrary.getAmountOut(amountADesired, poolA, poolC) > 10000);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
        addLiquidityStep.swapStepsA.push();
        addLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.SWAP;
        addLiquidityStep.swapStepsA[0].tokenOut = address(tokenC);
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(buttonswapFactory.getPair(address(tokenC), address(tokenB)), address(0), "Pair should not exist yet");

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        // Validating state
        address pairAddress = buttonswapFactory.getPair(address(tokenC), address(tokenB));
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be equal to amountADesired");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be equal to amountBDesired");
        assertEq(liquidity, MathExtended.sqrt(amountsA[1] * amountsB[0]) - 1000, "Liquidity should be equal geometric mean - 1000");
    }

    // Swapping B->C, then adding liquidity A+C
    function test_addLiquidity_createPairSingleSwapB(uint256 poolB, uint256 poolC, uint256 amountADesired, uint256 amountBDesired) public {
        // Creating an existing pair for the swap
        poolB = bound(poolB, 10000, type(uint112).max);
        poolC = bound(poolC, 10000, type(uint112).max);
        createAndInitializePair(tokenB, tokenC, poolB, poolC);

        // Minting enough for minimum liquidity requirement and not too much to mess up the A->C swap
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);
        vm.assume(amountBDesired < poolB);
        vm.assume(ButtonswapLibrary.getAmountOut(amountBDesired, poolB, poolC) > 10000);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
//        addLiquidityStep.swapStepsA; // Default to []
        addLiquidityStep.swapStepsB.push();
        addLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.SWAP;
        addLiquidityStep.swapStepsB[0].tokenOut = address(tokenC);
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(buttonswapFactory.getPair(address(tokenA), address(tokenC)), address(0), "Pair should not exist yet");

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        // Validating state
        address pairAddress = buttonswapFactory.getPair(address(tokenC), address(tokenB));
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be equal to amountADesired");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be equal to amountBDesired");
        assertEq(liquidity, MathExtended.sqrt(amountsA[0] * amountsB[1]) - 1000, "Liquidity should be equal geometric mean - 1000");
    }

    // Wrapping A->bA, then adding liquidity bA+B
    function test_addLiquidity_createPairSingleWrapButtonA(uint256 amountADesired, uint256 amountBDesired) public {
        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
        addLiquidityStep.swapStepsA.push();
        addLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.WRAP_BUTTON;
        addLiquidityStep.swapStepsA[0].tokenOut = address(buttonTokenA);
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(buttonswapFactory.getPair(address(buttonTokenA), address(tokenB)), address(0), "Pair should not exist yet");

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        // Validating state
        address pairAddress = buttonswapFactory.getPair(address(buttonTokenA), address(tokenB));
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be equal to amountADesired");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be equal to amountBDesired");
        assertEq(liquidity, MathExtended.sqrt(amountsA[1] * amountsB[0]) - 1000, "Liquidity should be equal geometric mean - 1000");
    }

    // Wrapping B->bB, then adding liquidity A+bB
    function test_addLiquidity_createPairSingleWrapButtonB(uint256 amountADesired, uint256 amountBDesired) public {
        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
//        addLiquidityStep.swapStepsA; // Default to []
        addLiquidityStep.swapStepsB.push();
        addLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.WRAP_BUTTON;
        addLiquidityStep.swapStepsB[0].tokenOut = address(buttonTokenB);
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(buttonswapFactory.getPair(address(tokenA), address(buttonTokenB)), address(0), "Pair should not exist yet");

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        // Validating state
        address pairAddress = buttonswapFactory.getPair(address(tokenA), address(buttonTokenB));
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be equal to amountADesired");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be equal to amountBDesired");
        assertEq(liquidity, MathExtended.sqrt(amountsA[0] * amountsB[1]) - 1000, "Liquidity should be equal geometric mean - 1000");
    }

    // Unwrapping bA->A, then adding liquidity A+B
    function test_addLiquidity_createPairSingleUnwrapButtonA(uint256 amountBADesired, uint256 amountBDesired) public {
        // Minting enough for minimum liquidity requirement
        amountBADesired = bound(amountBADesired, 10000, type(uint112).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);
        tokenA.mint(address(this), amountBADesired);
        tokenA.approve(address(buttonTokenA), amountBADesired);
        buttonTokenA.mint(amountBADesired);
        buttonTokenA.approve(address(genericButtonswapRouter), amountBADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(buttonTokenA);
        addLiquidityStep.tokenB = address(tokenB);
        addLiquidityStep.swapStepsA.push();
        addLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.UNWRAP_BUTTON;
        addLiquidityStep.swapStepsA[0].tokenOut = address(tokenA);
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountBADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(buttonswapFactory.getPair(address(tokenA), address(tokenB)), address(0), "Pair should not exist yet");

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        // Validating state
        address pairAddress = buttonswapFactory.getPair(address(tokenA), address(tokenB));
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountBADesired, "AmountsA[0] should be equal to amountBADesired");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be equal to amountBDesired");
        assertEq(liquidity, MathExtended.sqrt(amountsA[1] * amountsB[0]) - 1000, "Liquidity should be equal geometric mean - 1000");
    }

    // Unwrapping bB->B, then adding liquidity A+B
    function test_addLiquidity_createPairSingleUnwrapButtonB(uint256 amountADesired, uint256 amountBBDesired) public {
        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        amountBBDesired = bound(amountBBDesired, 10000, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBBDesired);
        tokenB.approve(address(buttonTokenB), amountBBDesired);
        buttonTokenB.mint(amountBBDesired);
        buttonTokenB.approve(address(genericButtonswapRouter), amountBBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(buttonTokenB);
//        addLiquidityStep.swapStepsA; // Default to []
        addLiquidityStep.swapStepsB.push();
        addLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.UNWRAP_BUTTON;
        addLiquidityStep.swapStepsB[0].tokenOut = address(tokenB);
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(buttonswapFactory.getPair(address(tokenA), address(tokenB)), address(0), "Pair should not exist yet");

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        // Validating state
        address pairAddress = buttonswapFactory.getPair(address(tokenA), address(tokenB));
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be equal to amountADesired");
        assertEq(amountsB[0], amountBBDesired, "AmountsB[0] should be equal to amountBBDesired");
        assertEq(liquidity, MathExtended.sqrt(amountsA[0] * amountsB[1]) - 1000, "Liquidity should be equal geometric mean - 1000");
    }

    // Wrapping ETH->WETH, then adding liquidity WETH+B
    function test_addLiquidity_createPairSingleWrapWethA(uint256 amountETHDesired, uint256 amountBDesired) public {
        // Minting enough for minimum liquidity requirement
        amountETHDesired = bound(amountETHDesired, 10000, type(uint112).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);
        vm.deal(address(this), amountETHDesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(0);
        addLiquidityStep.tokenB = address(tokenB);
        addLiquidityStep.swapStepsA.push();
        addLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.WRAP_WETH;
        addLiquidityStep.swapStepsA[0].tokenOut = address(weth);
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountETHDesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(buttonswapFactory.getPair(address(weth), address(tokenB)), address(0), "Pair should not exist yet");

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity{value: amountETHDesired}(addLiquidityStep, to, deadline);

        // Validating state
        address pairAddress = buttonswapFactory.getPair(address(weth), address(tokenB));
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountETHDesired, "AmountsA[0] should be equal to amountETHDesired");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be equal to amountBDesired");
        assertEq(liquidity, MathExtended.sqrt(amountsA[1] * amountsB[0]) - 1000, "Liquidity should be equal geometric mean - 1000");
    }

    // Wrapping ETH->WETH, then adding liquidity A+WETH
    function test_addLiquidity_createPairSingleWrapWethB(uint256 amountADesired, uint256 amountETHDesired) public {
        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        amountETHDesired = bound(amountETHDesired, 10000, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        vm.deal(address(this), amountETHDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(0);
//        addLiquidityStep.swapStepsA; // Default to []
        addLiquidityStep.swapStepsB.push();
        addLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.WRAP_WETH;
        addLiquidityStep.swapStepsB[0].tokenOut = address(weth);
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountETHDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 0;
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(buttonswapFactory.getPair(address(tokenA), address(weth)), address(0), "Pair should not exist yet");

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity{value: amountETHDesired}(addLiquidityStep, to, deadline);

        // Validating state
        address pairAddress = buttonswapFactory.getPair(address(tokenA), address(weth));
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be equal to amountADesired");
        assertEq(amountsB[0], amountETHDesired, "AmountsB[0] should be equal to amountETHDesired");
        assertEq(liquidity, MathExtended.sqrt(amountsA[0] * amountsB[1]) - 1000, "Liquidity should be equal geometric mean - 1000");
    }

    // singleUnwrapWeth not a viable test-cases since pairs can't accept raw-ETH

//    function test_addLiquidity_existingPairNoHops(uint256 amountADesired, uint256 amountBDesired) public {}
    function test_addLiquidity_pairExistsNoHops(uint256 poolA, uint256 poolB, uint256 amountADesired, uint256 amountBDesired) public {
        // Creating A-B pair with at least minimum liquidity
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Minting enough for depositing liquidity (minting at least 1/100th the existing liquidity)
        amountADesired = bound(amountADesired, poolA/100, type(uint112).max);
        amountBDesired = bound(amountBDesired, poolB/100, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
//        addLiquidityStep.swapStepsA; // Default to []
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        assertTrue(
            (amountsA[0] == amountADesired && amountsB[0] <= amountBDesired)
            || (amountsA[0] <= amountADesired && amountsB[0] == amountBDesired),
            "(AmountsA[0] = amountADesired and AmountsB[0] <= amountBDesired) OR (AmountsA[0] <= amountADesired and AmountsB[0] == amountBDesired)");
    }

    // Swapping A->C, then adding liquidity C+B
    function test_addLiquidity_existingPairSingleSwapA(uint256 poolA, uint256 poolC0, uint256 poolC1, uint poolB, uint256 amountADesired, uint256 amountBDesired) public {
        // Creating an existing A-C pair for the swap
        poolA = bound(poolA, 10000, type(uint112).max);
        poolC0 = bound(poolC0, 10000, type(uint112).max);
        createAndInitializePair(tokenA, tokenC, poolA, poolC0);

        // Creating a C-B pair with at least minimum liquidity
        poolC1 = bound(poolC1, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenC, tokenB, poolC1, poolB);

        // Minting enough for sufficient-output requirement but not too much to mess up the A->C swap
        amountADesired = bound(amountADesired, 1, poolA - 1);
        amountBDesired = bound(amountBDesired, poolB/100, type(uint112).max);
        uint256 amountCFromA = ButtonswapLibrary.getAmountOut(amountADesired, poolA, poolC0);
        uint256 amountCFromB = ButtonswapLibrary.quote(amountBDesired, poolB, poolC1);
        vm.assume(amountCFromA < poolC0 && amountCFromB < poolC0); // amountC < amount of C in B-C pair
        vm.assume(amountCFromA >= poolC1/100 && amountCFromB >= poolC1/100);

        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
        addLiquidityStep.swapStepsA.push();
        addLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.SWAP;
        addLiquidityStep.swapStepsA[0].tokenOut = address(tokenC);
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        assertTrue(
            (amountsA[0] == amountADesired && amountsB[0] <= amountBDesired)
            || (amountsA[0] <= amountADesired && amountsB[0] == amountBDesired),
            "(AmountsA[0] = amountADesired and AmountsB[0] <= amountBDesired) OR (AmountsA[0] <= amountADesired and AmountsB[0] == amountBDesired)");
    }

    // Swapping B->C, then adding liquidity A+C
    function test_addLiquidity_existingPairSingleSwapB(uint256 poolB, uint256 poolC0, uint256 poolA, uint poolC1, uint256 amountADesired, uint256 amountBDesired) public {
        // Creating an existing B-C pair for the swap
        poolB = bound(poolB, 10000, type(uint112).max);
        poolC0 = bound(poolC0, 10000, type(uint112).max);
        createAndInitializePair(tokenB, tokenC, poolB, poolC0);

        // Creating an A-C pair with at least minimum liquidity
        poolA = bound(poolA, 10000, type(uint112).max);
        poolC1 = bound(poolC1, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenC, poolA, poolC1);

        // Minting enough for sufficient-output requirement but not too much to mess up the B->C swap
        amountADesired = bound(amountADesired, poolA/100, type(uint112).max);
        amountBDesired = bound(amountBDesired, 1, poolB - 1);
        uint256 amountCFromA = ButtonswapLibrary.quote(amountADesired, poolA, poolC1);
        uint256 amountCFromB = ButtonswapLibrary.getAmountOut(amountBDesired, poolB, poolC0);
        vm.assume(amountCFromA < poolC0 && amountCFromB < poolC0); // amountC < amount of C in B-C pair
        vm.assume(amountCFromA >= poolC1/100 && amountCFromB >= poolC1/100);

        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
//        addLiquidityStep.swapStepsA; // Default to []
        addLiquidityStep.swapStepsB.push();
        addLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.SWAP;
        addLiquidityStep.swapStepsB[0].tokenOut = address(tokenC);
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        assertTrue(
            (amountsA[0] == amountADesired && amountsB[0] <= amountBDesired)
            || (amountsA[0] <= amountADesired && amountsB[0] == amountBDesired),
            "(AmountsA[0] = amountADesired and AmountsB[0] <= amountBDesired) OR (AmountsA[0] <= amountADesired and AmountsB[0] == amountBDesired)");
    }

    // Wrapping A->bA, then adding liquidity bA+B
    function test_addLiquidity_existingPairSingleWrapButtonA(uint256 poolButtonA, uint poolB, uint256 amountADesired, uint256 amountBDesired) public {
        // Creating bA-B pair with at least minimum liquidity
        poolButtonA = bound(poolButtonA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairButton(tokenB, buttonTokenA, poolB, poolButtonA);

        // Minting enough for depositing liquidity (minting at least 1/100th of the existing liquidity)
        amountADesired = bound(amountADesired, buttonTokenA.wrapperToUnderlying(poolButtonA)/100, type(uint112).max);
        amountBDesired = bound(amountBDesired, poolB/100, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
        addLiquidityStep.swapStepsA.push();
        addLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.WRAP_BUTTON;
        addLiquidityStep.swapStepsA[0].tokenOut = address(buttonTokenA);
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        assertTrue(
            (amountsA[0] == amountADesired && amountsB[0] <= amountBDesired)
            || (amountsA[0] <= amountADesired && amountsB[0] == amountBDesired),
            "(AmountsA[0] = amountADesired and AmountsB[0] <= amountBDesired) OR (AmountsA[0] <= amountADesired and AmountsB[0] == amountBDesired)");
    }

    // Wrapping B->bB, then adding liquidity A+bB
    function test_addLiquidity_existingPairSingleWrapButtonB(uint256 poolA, uint poolButtonB, uint256 amountADesired, uint256 amountBDesired) public {
        // Creating A-bB pair with at least minimum liquidity
        poolA = bound(poolA, 10000, type(uint112).max);
        poolButtonB = bound(poolButtonB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairButton(tokenA, buttonTokenB, poolA, poolButtonB);

        // Minting enough for depositing liquidity (minting at least 1/100th of the existing liquidity)
        amountADesired = bound(amountADesired, poolA/100, type(uint112).max);
        amountBDesired = bound(amountBDesired, buttonTokenB.wrapperToUnderlying(poolButtonB)/100, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(tokenB);
//        addLiquidityStep.swapStepsA; // Default to []
        addLiquidityStep.swapStepsB.push();
        addLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.WRAP_BUTTON;
        addLiquidityStep.swapStepsB[0].tokenOut = address(buttonTokenB);
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        assertTrue(
            (amountsA[0] == amountADesired && amountsB[0] <= amountBDesired)
            || (amountsA[0] <= amountADesired && amountsB[0] == amountBDesired),
            "(AmountsA[0] = amountADesired and AmountsB[0] <= amountBDesired) OR (AmountsA[0] <= amountADesired and AmountsB[0] == amountBDesired)");
    }

    // Unwrapping bA->A, then adding liquidity A+B
    function test_addLiquidity_existingPairSingleUnwrapButtonA(uint256 poolA, uint poolB, uint256 amountButtonADesired, uint256 amountBDesired) public {
        // Creating A-B pair with at least minimum liquidity
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Minting enough for depositing liquidity (minting at least 1/100th of the existing liquidity)
        amountButtonADesired = bound(amountButtonADesired, buttonTokenA.underlyingToWrapper(poolA)/100, type(uint112).max);
        amountBDesired = bound(amountBDesired, poolB/100, type(uint112).max);
        uint256 amountTokenA = buttonTokenA.wrapperToUnderlying(amountButtonADesired);
        tokenA.mint(address(this), amountTokenA);
        tokenA.approve(address(buttonTokenA), amountTokenA);
        buttonTokenA.mint(amountButtonADesired);
        buttonTokenA.approve(address(genericButtonswapRouter), amountButtonADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(buttonTokenA);
        addLiquidityStep.tokenB = address(tokenB);
        addLiquidityStep.swapStepsA.push();
        addLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.UNWRAP_BUTTON;
        addLiquidityStep.swapStepsA[0].tokenOut = address(tokenA);
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountButtonADesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        assertTrue(
            (amountsA[0] == amountButtonADesired && amountsB[0] <= amountBDesired)
            || (amountsA[0] <= amountButtonADesired && amountsB[0] == amountBDesired),
            "(AmountsA[0] = amountButtonADesired and AmountsB[0] <= amountBDesired) OR (AmountsA[0] <= amountButtonADesired and AmountsB[0] == amountBDesired)");
    }

    // Unwrapping bB->B, then adding liquidity A+B
    function test_addLiquidity_existingPairSingleUnwrapButtonB(uint256 poolA, uint poolB, uint256 amountADesired, uint256 amountButtonBDesired) public {
        // Creating A-B pair with at least minimum liquidity
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Minting enough for depositing liquidity (minting at least 1/100th of the existing liquidity)
        amountADesired = bound(amountADesired, poolA/100, type(uint112).max);
        amountButtonBDesired = bound(amountButtonBDesired, buttonTokenB.underlyingToWrapper(poolB)/100, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        uint256 amountTokenB = buttonTokenB.wrapperToUnderlying(amountButtonBDesired);
        tokenB.mint(address(this), amountTokenB);
        tokenB.approve(address(buttonTokenB), amountTokenB);
        buttonTokenB.mint(amountButtonBDesired);
        buttonTokenB.approve(address(genericButtonswapRouter), amountButtonBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(buttonTokenB);
//        addLiquidityStep.swapStepsA; // Default to []
        addLiquidityStep.swapStepsB.push();
        addLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.UNWRAP_BUTTON;
        addLiquidityStep.swapStepsB[0].tokenOut = address(tokenB);
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountButtonBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity(addLiquidityStep, to, deadline);

        assertTrue(
            (amountsA[0] == amountADesired && amountsB[0] <= amountButtonBDesired)
            || (amountsA[0] <= amountADesired && amountsB[0] == amountButtonBDesired),
            "(AmountsA[0] = amountADesired and AmountsB[0] <= amountButtonBDesired) OR (AmountsA[0] <= amountADesired and AmountsB[0] == amountButtonBDesired)");
    }

    // Wrapping ETH->WETH, then adding liquidity WETH+B
    function test_addLiquidity_existingPairSingleWrapWethA(uint256 poolWETH, uint poolB, uint256 amountETHDesired, uint256 amountBDesired) public {
        // Creating bA-B pair with at least minimum liquidity
        poolWETH = bound(poolWETH, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenB, poolB, poolWETH);

        // Minting enough for depositing liquidity (minting at least 1/100th of the existing liquidity)
        amountETHDesired = bound(amountETHDesired, poolWETH/100, type(uint112).max);
        amountBDesired = bound(amountBDesired, poolB/100, type(uint112).max);
        vm.deal(address(this), amountETHDesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(0);
        addLiquidityStep.tokenB = address(tokenB);
        addLiquidityStep.swapStepsA.push();
        addLiquidityStep.swapStepsA[0].operation = ButtonswapOperations.Swap.WRAP_WETH;
        addLiquidityStep.swapStepsA[0].tokenOut = address(weth);
//        addLiquidityStep.swapStepsB; // Default to []
        addLiquidityStep.amountADesired = amountETHDesired;
        addLiquidityStep.amountBDesired = amountBDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity{value: amountETHDesired}(addLiquidityStep, to, deadline);

        assertTrue(
            (amountsA[0] == amountETHDesired && amountsB[0] <= amountBDesired)
            || (amountsA[0] <= amountETHDesired && amountsB[0] == amountBDesired),
            "(AmountsA[0] = amountETHDesired and AmountsB[0] <= amountBDesired) OR (AmountsA[0] <= amountETHDesired and AmountsB[0] == amountBDesired)");
    }

    // Wrapping ETH->WETH, then adding liquidity A+WETH
    function test_addLiquidity_existingPairSingleWrapWethB(uint256 poolA, uint poolWETH, uint256 amountADesired, uint256 amountETHDesired) public {
        // Creating bA-B pair with at least minimum liquidity
        poolA = bound(poolA, 10000, type(uint112).max);
        poolWETH = bound(poolWETH, 10000, type(uint112).max);
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenA, poolA, poolWETH);

        // Minting enough for depositing liquidity (minting at least 1/100th of the existing liquidity)
        amountADesired = bound(amountADesired, poolA/100, type(uint112).max);
        amountETHDesired = bound(amountETHDesired, poolWETH/100, type(uint112).max);
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        vm.deal(address(this), amountETHDesired);

        // Creating the addLiquidityStep
        addLiquidityStep.operation = ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY; // Potentially just separate out the function
        addLiquidityStep.tokenA = address(tokenA);
        addLiquidityStep.tokenB = address(0);
//        addLiquidityStep.swapStepsA; // Default to []
        addLiquidityStep.swapStepsB.push();
        addLiquidityStep.swapStepsB[0].operation = ButtonswapOperations.Swap.WRAP_WETH;
        addLiquidityStep.swapStepsB[0].tokenOut = address(weth);
        addLiquidityStep.amountADesired = amountADesired;
        addLiquidityStep.amountBDesired = amountETHDesired;
        addLiquidityStep.amountAMin = 0;
        addLiquidityStep.amountBMin = 0;
        addLiquidityStep.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) = genericButtonswapRouter.addLiquidity{value: amountETHDesired}(addLiquidityStep, to, deadline);

        assertTrue(
            (amountsA[0] == amountADesired && amountsB[0] <= amountETHDesired)
            || (amountsA[0] <= amountADesired && amountsB[0] == amountETHDesired),
            "(AmountsA[0] = amountADesired and AmountsB[0] <= amountETHDesired) OR (AmountsA[0] <= amountADesired and AmountsB[0] == amountETHDesired)");
    }
}
