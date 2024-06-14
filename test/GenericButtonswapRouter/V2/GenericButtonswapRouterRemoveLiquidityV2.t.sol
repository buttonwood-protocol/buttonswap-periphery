// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapPairErrors} from
    "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPairErrors.sol";
import {IGenericButtonswapRouter} from "../../../src/interfaces/IButtonswapRouter/IGenericButtonswapRouter.sol";
import {IGenericButtonswapRouterErrors} from
    "../../../src/interfaces/IButtonswapRouter/IGenericButtonswapRouterErrors.sol";
import {GenericButtonswapRouter} from "../../../src/GenericButtonswapRouter.sol";
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {ButtonswapOperations} from "../../../src/libraries/ButtonswapOperations.sol";
import {PairMath} from "buttonswap-periphery_buttonswap-core/libraries/PairMath.sol";
import {IButtonswapPairErrors} from
    "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPairErrors.sol";
import {MathExtended} from "../../utils/MathExtended.sol";
import {MockERC20} from "buttonswap-periphery_mock-contracts/MockERC20.sol";
import {IButtonswapV2Pair} from
    "buttonswap-periphery_buttonswap-v2-core/interfaces/IButtonswapV2Pair/IButtonswapV2Pair.sol";
import {ButtonswapV2Factory} from "buttonswap-periphery_buttonswap-v2-core/ButtonswapV2Factory.sol";
import {ButtonswapV2FactoryHelper} from "buttonswap-periphery_buttonswap-v2-core/ButtonswapV2FactoryHelper.sol";
import {IButtonswapV2Factory} from
    "buttonswap-periphery_buttonswap-v2-core/interfaces/IButtonswapV2Factory/IButtonswapV2Factory.sol";
import {ButtonswapV2Library} from "../../../src/libraries/ButtonswapV2Library.sol";

contract GenericButtonswapRouterRemoveLiquidityV2Test is Test, IGenericButtonswapRouterErrors {
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
    ButtonswapV2Factory public buttonswapV2Factory;
    ButtonswapV2FactoryHelper public buttonswapV2FactoryHelper;
    IButtonswapV2Factory.PairCreationParameters public defaultPairCreationParameters;
    GenericButtonswapRouter public genericButtonswapRouter;
    IGenericButtonswapRouter.RemoveLiquidityParams public removeLiquidityParams;

    // Utility function for creating and initializing pairs with poolA:poolB price ratio. Does not use ButtonwoodRouter
    function createAndInitializePair(
        MockRebasingERC20 tokenA1,
        MockRebasingERC20 tokenB1,
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps
    ) private returns (IButtonswapV2Pair pair, uint256 liquidityOut) {
        pair = IButtonswapV2Pair(buttonswapV2Factory.createPair(address(tokenA1), address(tokenB1), plBps, feeBps));
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

    function setupButtonswapV2FactoryParameters(uint16 plBps, uint16 feeBps) private {
        vm.prank(paramSetter);
        buttonswapV2Factory.setDefaultParameters(
            plBps,
            feeBps,
            defaultPairCreationParameters.movingAverageWindow,
            defaultPairCreationParameters.maxVolatilityBps,
            defaultPairCreationParameters.minTimelockDuration,
            defaultPairCreationParameters.maxTimelockDuration,
            defaultPairCreationParameters.maxSwappableReservoirLimitBps,
            defaultPairCreationParameters.swappableReservoirGrowthWindow,
            defaultPairCreationParameters.protocolFeeMbps,
            defaultPairCreationParameters.minSiphonDuration,
            defaultPairCreationParameters.maxSiphonDuration
        );
    }

    // Utility function for testing functions that use Permit
    function generateUserPermitSignature(
        address user,
        uint256 userPrivateKey,
        IButtonswapV2Pair pair,
        uint256 liquidity,
        uint256 deadline
    ) private view returns (uint8 v, bytes32 r, bytes32 s) {
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

    function encodeV2Data(uint16 plBps, uint16 feeBps) private pure returns (bytes memory) {
        return abi.encodePacked(uint8(2), plBps, feeBps);
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

        buttonswapV2FactoryHelper = new ButtonswapV2FactoryHelper();
        buttonswapV2Factory = new ButtonswapV2Factory(
            feeToSetter,
            isCreationRestrictedSetter,
            isPausedSetter,
            paramSetter,
            "Token Name",
            "SYMBOL",
            address(buttonswapV2FactoryHelper)
        );

        // Set the defaults that will be used for the creation of new pairs
        defaultPairCreationParameters.movingAverageWindow = 24 hours;
        defaultPairCreationParameters.maxVolatilityBps = 700;
        defaultPairCreationParameters.minTimelockDuration = 24 seconds;
        defaultPairCreationParameters.maxTimelockDuration = 24 hours;
        defaultPairCreationParameters.maxSwappableReservoirLimitBps = 500;
        defaultPairCreationParameters.swappableReservoirGrowthWindow = 24 hours;
        defaultPairCreationParameters.protocolFeeMbps = 5000;
        defaultPairCreationParameters.minSiphonDuration = 24 seconds;
        defaultPairCreationParameters.maxSiphonDuration = 24 hours;

        genericButtonswapRouter = new GenericButtonswapRouter(address(0), address(buttonswapV2Factory), address(0));
    }

    function test_removeLiquidity_expiredDeadline(uint256 timestamp, uint256 deadline) public {
        // Skipping block.timestamp to after the deadline
        vm.assume(timestamp > deadline);
        vm.warp(timestamp);
        address to = address(this);

        // Don't need to build any parameters since deadline is the first check that should fail

        // Attempting to add liquidity with an expired deadline
        vm.expectRevert(
            abi.encodeWithSelector(IGenericButtonswapRouterErrors.Expired.selector, deadline, block.timestamp)
        );
        genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);
    }

    function test_removeLiquidity_pairDoesNotExist(
        address tokenA1,
        address tokenB1,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity
    ) public {
        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 0, type(uint112).max);

        // Validating pair doesn't exist
        assertEq(
            buttonswapV2Factory.getPair(address(tokenA1), address(tokenB1), plBps, feeBps),
            address(0),
            "Pair should not exist"
        );

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL;
        removeLiquidityParams.tokenA = address(tokenA1);
        removeLiquidityParams.tokenB = address(tokenB1);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove liquidity from a non-existent pair
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.PairDoesNotExist.selector, address(tokenA1), address(tokenB1)
            )
        );
        genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);
    }

    function test_removeLiquidity_insufficientAmountA(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity,
        uint256 amountAMin
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA returned from removing liquidity
        uint256 amountA = (poolA * liquidity) / pair.totalSupply();
        // Guaranteeing that the amountAMin is greater than the amountA returned
        vm.assume(amountAMin > amountA);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = amountAMin;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove liquidity
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector, address(tokenA), amountA, amountAMin
            )
        );
        genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);
    }

    function test_removeLiquidity_insufficientAmountB(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity,
        uint256 amountBMin
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountB returned from removing liquidity
        uint256 amountB = (poolB * liquidity) / pair.totalSupply();
        // Guaranteeing that the amountAMin is greater than the amountA returned
        vm.assume(amountBMin > amountB);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = amountBMin;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove liquidity
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector, address(tokenB), amountB, amountBMin
            )
        );
        genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);
    }

    function test_removeLiquidity_noHops(uint256 poolA, uint256 poolB, uint16 plBps, uint16 feeBps, uint256 liquidity)
        public
    {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        uint256 expectedAmountA = (poolA * liquidity) / pair.totalSupply();
        uint256 expectedAmountB = (poolB * liquidity) / pair.totalSupply();

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidity);

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) =
            genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    function test_removeLiquidity_noHopsWithReservoir(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        bool aOrB
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

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

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) =
            genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    function test_removeLiquidityFromReservoir_pairDoesNotExist(
        address tokenA1,
        address tokenB1,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Validating pair doesn't exist
        assertEq(
            buttonswapV2Factory.getPair(address(tokenA1), address(tokenB1), plBps, feeBps),
            address(0),
            "Pair should not exist"
        );

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        removeLiquidityParams.tokenA = address(tokenA1);
        removeLiquidityParams.tokenB = address(tokenB1);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove liquidity from a non-existent pair
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.PairDoesNotExist.selector, address(tokenA1), address(tokenB1)
            )
        );
        genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);
    }

    function test_removeLiquidityFromReservoir_noReservoir(uint256 poolA, uint256 poolB, uint16 plBps, uint16 feeBps)
        public
    {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Approving the router to use the pair-tokens
        pair.approve(address(genericButtonswapRouter), liquidityOut);

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidityOut;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to remove all the liquidity from a pair with no reservoir
        vm.expectRevert(abi.encodeWithSelector(IButtonswapPairErrors.InsufficientReservoir.selector));
        genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);
    }

    function test_removeLiquidityFromReservoir_reservoirAInsufficientTokenAmount(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        bool insufficientAOrB
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

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
        (uint256 tokenOutA, uint256 swappedReservoirAmountA) =
            ButtonswapV2Library.getBurnSwappedAmounts(address(pair), address(tokenA), address(tokenB), liquidity);
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

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        // Ensuring insufficient token output
        if (insufficientAOrB) {
            removeLiquidityParams.amountAMin = tokenOutA + 1;
            removeLiquidityParams.amountBMin = 0;
        } else {
            removeLiquidityParams.amountAMin = 0;
            removeLiquidityParams.amountBMin = 1;
        }
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to removing liquidity with insufficient amount
        if (insufficientAOrB) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector,
                    address(tokenA),
                    tokenOutA,
                    tokenOutA + 1
                )
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector, address(tokenB), 0, 1
                )
            );
        }
        genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);
    }

    function test_removeLiquidityFromReservoir_reservoirBInsufficientTokenAmount(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        bool insufficientAOrB
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

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
        (uint256 tokenOutB, uint256 swappedReservoirAmountB) =
            ButtonswapV2Library.getBurnSwappedAmounts(address(pair), address(tokenB), address(tokenA), liquidity);
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

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        // Ensuring insufficient token output
        if (insufficientAOrB) {
            removeLiquidityParams.amountAMin = 1;
            removeLiquidityParams.amountBMin = 0;
        } else {
            removeLiquidityParams.amountAMin = 0;
            removeLiquidityParams.amountBMin = tokenOutB + 1;
        }
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
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
                    IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector,
                    address(tokenB),
                    tokenOutB,
                    tokenOutB + 1
                )
            );
        }
        genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);
    }

    function test_removeLiquidityFromReservoir_reservoirANoHops(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

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
        (uint256 tokenOutA, uint256 swappedReservoirAmountA) =
            ButtonswapV2Library.getBurnSwappedAmounts(address(pair), address(tokenA), address(tokenB), liquidity);
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

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) =
            genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], tokenOutA, "AmountsA[0] should equal tokenOutA");
        assertEq(amountsB.length, 0, "AmountsB should be empty");
    }

    function test_removeLiquidityFromReservoir_reservoirBNoHops(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

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
        (uint256 tokenOutB, uint256 swappedReservoirAmountB) =
            ButtonswapV2Library.getBurnSwappedAmounts(address(pair), address(tokenB), address(tokenA), liquidity);
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

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Removing liquidity
        (uint256[] memory amountsA, uint256[] memory amountsB) =
            genericButtonswapRouter.removeLiquidity(removeLiquidityParams, to, deadline);

        // Validating the amountA/amountB returned
        assertEq(amountsA.length, 0, "AmountsA should be empty");
        assertEq(amountsB[0], tokenOutB, "AmountsB[0] should equal tokenOutB");
    }

    function test_removeLiquidityWithPermit_specificPermission(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Transferring pair liquidity to userA to test out the permit functionality
        pair.transfer(userA, liquidityOut);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        uint256 expectedAmountA = (poolA * liquidity) / pair.totalSupply();
        uint256 expectedAmountB = (poolB * liquidity) / pair.totalSupply();

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserPermitSignature(userA, userAPrivateKey, pair, liquidity, deadline);

        // Removing liquidity as userA
        vm.prank(userA);
        (uint256[] memory amountsA, uint256[] memory amountsB) =
            genericButtonswapRouter.removeLiquidityWithPermit(removeLiquidityParams, to, deadline, false, v, r, s);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }

    function test_removeLiquidityWithPermit_MaxPermission(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 liquidity
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair, uint256 liquidityOut) =
            createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Transferring pair liquidity to userA to test out the permit functionality
        pair.transfer(userA, liquidityOut);

        // Bound liquidity to be within the range of any pair's liquidity
        liquidity = bound(liquidity, 1, liquidityOut);

        // Estimating amountA/amountB returned from removing liquidity
        uint256 expectedAmountA = (poolA * liquidity) / pair.totalSupply();
        uint256 expectedAmountB = (poolB * liquidity) / pair.totalSupply();

        // Creating the removeLiquidityParams
        removeLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL;
        removeLiquidityParams.tokenA = address(tokenA);
        removeLiquidityParams.tokenB = address(tokenB);
        //        removeLiquidityParams.swapStepsA; // Default to []
        //        removeLiquidityParams.swapStepsB; // Default to []
        removeLiquidityParams.liquidity = liquidity;
        removeLiquidityParams.amountAMin = 0;
        removeLiquidityParams.amountBMin = 0;
        removeLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) =
            generateUserPermitSignature(userA, userAPrivateKey, pair, type(uint256).max, deadline);

        // Removing liquidity as userA
        vm.prank(userA);
        (uint256[] memory amountsA, uint256[] memory amountsB) =
            genericButtonswapRouter.removeLiquidityWithPermit(removeLiquidityParams, to, deadline, true, v, r, s);

        // Validating the amountA/amountB returned
        assertEq(amountsA[0], expectedAmountA, "AmountsA[0] should equal expectedAmountA");
        assertEq(amountsB[0], expectedAmountB, "AmountsB[0] should equal expectedAmountB");
    }
}
