// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// ToDo: 1. Remove all v1 deps and rewrite with v2
import {Test} from "buttonswap-periphery_forge-std/Test.sol";
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
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {IButtonswapV2Pair} from
    "buttonswap-periphery_buttonswap-v2-core/interfaces/IButtonswapV2Pair/IButtonswapV2Pair.sol";
import {ButtonswapV2Factory} from "buttonswap-periphery_buttonswap-v2-core/ButtonswapV2Factory.sol";
import {ButtonswapV2FactoryHelper} from "buttonswap-periphery_buttonswap-v2-core/ButtonswapV2FactoryHelper.sol";
import {IButtonswapV2Factory} from
    "buttonswap-periphery_buttonswap-v2-core/interfaces/IButtonswapV2Factory/IButtonswapV2Factory.sol";
import {PairMathV2} from "buttonswap-periphery_buttonswap-v2-core/libraries/PairMathV2.sol";
import {ButtonswapV2Library} from "../../../src/libraries/ButtonswapV2Library.sol";

contract GenericButtonswapRouterAddLiquidityV2Test is Test, IGenericButtonswapRouterErrors {
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
    IGenericButtonswapRouter.AddLiquidityParams public addLiquidityParams;

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
            defaultPairCreationParameters.minBasinDuration,
            defaultPairCreationParameters.maxBasinDuration
        );
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
        defaultPairCreationParameters.minBasinDuration = 24 seconds;
        defaultPairCreationParameters.maxBasinDuration = 24 hours;

        genericButtonswapRouter = new GenericButtonswapRouter(address(0), address(buttonswapV2Factory), address(0));
    }

    function test_addLiquidity_expiredDeadline(uint256 timestamp, uint256 deadline) public {
        // Skipping block.timestamp to after the deadline
        vm.assume(timestamp > deadline);
        vm.warp(timestamp);
        address to = address(this);

        // Don't need to build any parameters since deadline is the first check that should fail

        // Attempting to add liquidity with an expired deadline
        vm.expectRevert(
            abi.encodeWithSelector(IGenericButtonswapRouterErrors.Expired.selector, deadline, block.timestamp)
        );
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function test_addLiquidity_createPairNoHops(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 liquidityMin,
        uint16 plBps,
        uint16 feeBps
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint104).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint104).max);

        // Ensuring expectedLiquidity is over liquidityMin
        uint256 expectedLiquidity = PairMathV2.k(amountADesired, amountBDesired, plBps) - 1000;
        liquidityMin = bound(liquidityMin, 0, expectedLiquidity - 1);

        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL; // Potentially just separate out the function
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = amountADesired;
        addLiquidityParams.amountBDesired = amountBDesired;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = true;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(
            buttonswapV2Factory.getPair(address(tokenA), address(tokenB), plBps, feeBps),
            address(0),
            "Pair should not exist yet"
        );

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) =
            genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);

        // Validating state
        address pairAddress = buttonswapV2Factory.getPair(address(tokenA), address(tokenB), plBps, feeBps);
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be equal to amountADesired");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be equal to amountBDesired");
        assertEq(liquidity, expectedLiquidity, "Liquidity should be equal K-value - 1000");
    }

    function test_addLiquidity_createPairNoHopsMovingAveragePrice0ThresholdExceeds100Percent(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 liquidityMin,
        uint16 plBps,
        uint16 feeBps,
        uint256 movingAveragePrice0ThresholdBps
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint104).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint104).max);
        movingAveragePrice0ThresholdBps = bound(movingAveragePrice0ThresholdBps, 10001, type(uint256).max);

        // Ensuring expectedLiquidity is over liquidityMin
        uint256 expectedLiquidity = PairMathV2.k(amountADesired, amountBDesired, plBps) - 1000;
        liquidityMin = bound(liquidityMin, 0, expectedLiquidity - 1);

        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL; // Potentially just separate out the function
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = amountADesired;
        addLiquidityParams.amountBDesired = amountBDesired;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = movingAveragePrice0ThresholdBps;
        addLiquidityParams.createPair = true;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(
            buttonswapV2Factory.getPair(address(tokenA), address(tokenB), plBps, feeBps),
            address(0),
            "Pair should not exist yet"
        );

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) =
            genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);

        // Validating state
        address pairAddress = buttonswapV2Factory.getPair(address(tokenA), address(tokenB), plBps, feeBps);
        assertNotEq(pairAddress, address(0), "Pair should now exist");
        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be equal to amountADesired");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be equal to amountBDesired");
        assertEq(liquidity, expectedLiquidity, "Liquidity should be equal geometric mean - 1000");
    }

    function test_addLiquidity_createPairNoHopsPairDoesNotExist(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 liquidityMin,
        uint16 plBps,
        uint16 feeBps
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint104).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint104).max);

        // Ensuring expectedLiquidity is over liquidityMin
        uint256 expectedLiquidity = PairMathV2.k(amountADesired, amountBDesired, plBps) - 1000;
        liquidityMin = bound(liquidityMin, 0, expectedLiquidity - 1);

        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL; // Potentially just separate out the function
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = amountADesired;
        addLiquidityParams.amountBDesired = amountBDesired;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(
            buttonswapV2Factory.getPair(address(tokenA), address(tokenB), plBps, feeBps),
            address(0),
            "Pair should not exist yet"
        );

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Attempt to create the pair with createPair parameter set to false;
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.PairDoesNotExist.selector, address(tokenA), address(tokenB)
            )
        );
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function test_addLiquidity_createPairNoHopsInsufficientOutputLiquidity(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 liquidityMin,
        uint16 plBps,
        uint16 feeBps
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint104).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint104).max);

        // Ensuring liquidityMin is higher than expected liquidity to throw error
        uint256 expectedLiquidity = PairMathV2.k(amountADesired, amountBDesired, plBps) - 1000;
        liquidityMin = bound(liquidityMin, expectedLiquidity + 1, type(uint256).max);

        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL; // Potentially just separate out the function
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = amountADesired;
        addLiquidityParams.amountBDesired = amountBDesired;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = liquidityMin;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = true;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(
            buttonswapV2Factory.getPair(address(tokenA), address(tokenB), plBps, feeBps),
            address(0),
            "Pair should not exist yet"
        );

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Attempt to create the pair with insufficient liquidity
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.InsufficientOutputLiquidity.selector, expectedLiquidity, liquidityMin
            )
        );
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function test_addLiquidity_pairExistsNoHops(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 liquidityMin
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with higher liquidity than the minimum to account for precision errors in MockRebasingERC20
        poolA = bound(poolA, 100_000, type(uint104).max);
        poolB = bound(poolB, 100_000, type(uint104).max);
        (IButtonswapV2Pair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Minting enough for depositing liquidity (minting at least 1/100th the existing liquidity)
        amountADesired = bound(amountADesired, poolA / 100, type(uint104).max);
        amountBDesired = bound(amountBDesired, poolB / 100, type(uint104).max);

        // Solving for the expected liquidity
        uint256 expectedLiquidity = (pair.totalSupply() * amountADesired) / tokenA.balanceOf(address(pair));
        if (expectedLiquidity > (pair.totalSupply() * amountBDesired) / tokenB.balanceOf(address(pair))) {
            expectedLiquidity = (pair.totalSupply() * amountBDesired) / tokenB.balanceOf(address(pair));
        }

        // Ensuring expectedLiquidity is higher than liquidityMin (accounting for precision errors in MockRebasingERC20)
        liquidityMin = bound(liquidityMin, 0, (expectedLiquidity * (0.99e18)) / (1e18));

        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL; // Potentially just separate out the function
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = amountADesired;
        addLiquidityParams.amountBDesired = amountBDesired;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = liquidityMin;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Adding liquidity to the pair
        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) =
            genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);

        assertTrue(
            (amountsA[0] == amountADesired && amountsB[0] <= amountBDesired)
                || (amountsA[0] <= amountADesired && amountsB[0] == amountBDesired),
            "(AmountsA[0] = amountADesired and AmountsB[0] <= amountBDesired) OR (AmountsA[0] <= amountADesired and AmountsB[0] == amountBDesired)"
        );
        // Using approx-EQ because of precision errors in MockRebasingERC20
        assertApproxEqRel(liquidity, expectedLiquidity, 0.01e18, "Liquidity should be equal to expectedLiquidity");
    }

    function test_addLiquidity_pairExistsNoHopsPairAlreadyExists(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 liquidityMin
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with higher liquidity than the minimum to account for precision errors in MockRebasingERC20
        poolA = bound(poolA, 100_000, type(uint104).max);
        poolB = bound(poolB, 100_000, type(uint104).max);
        (IButtonswapV2Pair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Minting enough for depositing liquidity (minting at least 1/100th the existing liquidity)
        amountADesired = bound(amountADesired, poolA / 100, type(uint104).max);
        amountBDesired = bound(amountBDesired, poolB / 100, type(uint104).max);

        // Solving for the expected liquidity
        uint256 expectedLiquidity = (pair.totalSupply() * amountADesired) / tokenA.balanceOf(address(pair));
        if (expectedLiquidity > (pair.totalSupply() * amountBDesired) / tokenB.balanceOf(address(pair))) {
            expectedLiquidity = (pair.totalSupply() * amountBDesired) / tokenB.balanceOf(address(pair));
        }

        // Ensuring expectedLiquidity is higher than liquidityMin (accounting for precision errors in MockRebasingERC20)
        liquidityMin = bound(liquidityMin, 0, (expectedLiquidity * (0.99e18)) / (1e18));

        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL; // Potentially just separate out the function
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = amountADesired;
        addLiquidityParams.amountBDesired = amountBDesired;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = liquidityMin;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        addLiquidityParams.createPair = true;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempt to add liquidity to the pair with create parameter set to true even though it already exists
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.PairAlreadyExists.selector,
                address(tokenA),
                address(tokenB),
                address(pair)
            )
        );
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function test_addLiquidity_pairExistsNoHopsInsufficientOutputLiquidity(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 liquidityMin
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with higher liquidity than the minimum to account for precision errors in MockRebasingERC20
        poolA = bound(poolA, 100_000, type(uint104).max);
        poolB = bound(poolB, 100_000, type(uint104).max);
        (IButtonswapV2Pair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Minting enough for depositing liquidity (minting at least 1/100th the existing liquidity)
        amountADesired = bound(amountADesired, poolA / 100, type(uint104).max);
        amountBDesired = bound(amountBDesired, poolB / 100, type(uint104).max);

        // Solving for the expected liquidity
        uint256 expectedLiquidity = (pair.totalSupply() * amountADesired) / tokenA.balanceOf(address(pair));
        if (expectedLiquidity > (pair.totalSupply() * amountBDesired) / tokenB.balanceOf(address(pair))) {
            expectedLiquidity = (pair.totalSupply() * amountBDesired) / tokenB.balanceOf(address(pair));
        }

        // Ensuring expectedLiquidity is lower than liquidityMin (accounting for precision errors in MockRebasingERC20)
        liquidityMin = bound(liquidityMin, expectedLiquidity + 1, type(uint256).max);

        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.DUAL; // Potentially just separate out the function
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = amountADesired;
        addLiquidityParams.amountBDesired = amountBDesired;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = liquidityMin;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 1; // Giving it 1 basis-point of slack because rounding from the 2**112 conversion
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempt to create the pair with insufficient liquidity
        // Can't check for revert reason because of precision errors when predicting the expectedLiquidity
        vm.expectRevert();
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function test_addLiquidityWithReservoir_revertWhenPairDoesNotExist(uint16 plBps, uint16 feeBps) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating new tokens to ensure the pair does not exist
        tokenA = new MockRebasingERC20("TokenA", "TKNA", 18);
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = 0;
        addLiquidityParams.amountBDesired = 0;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does not exist yet
        assertEq(
            buttonswapV2Factory.getPair(address(tokenA), address(tokenB), plBps, feeBps),
            address(0),
            "Pair should not exist yet"
        );

        // Attempting to addLiquidityWithReservoir to the pair
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.PairDoesNotExist.selector, address(tokenA), address(tokenB)
            )
        );
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function test_addLiquidityWithReservoir_revertWhenPairIsNotInitialized(
        bytes32 saltA,
        bytes32 saltB,
        uint16 plBps,
        uint16 feeBps
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Re-assigning tokenA and tokenB to ensure random new pair
        tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        // Creating random A1-B1 pair without initializing
        address pair = buttonswapV2Factory.createPair(address(tokenA), address(tokenB), plBps, feeBps);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = 0;
        addLiquidityParams.amountBDesired = 0;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Validate the pair does exist now
        assertNotEq(
            buttonswapV2Factory.getPair(address(tokenA), address(tokenB), plBps, feeBps),
            address(0),
            "Pair should exist"
        );

        // Attempting to addLiquidityWithReservoir to the pair
        vm.expectRevert(abi.encodeWithSelector(IGenericButtonswapRouterErrors.NotInitialized.selector, pair));
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function test_addLiquidityWithReservoir_revertWhenReservoirDoesNotExist(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = 0;
        addLiquidityParams.amountBDesired = 0;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to addLiquidityWithReservoir to the pair
        vm.expectRevert(abi.encodeWithSelector(IGenericButtonswapRouterErrors.NoReservoir.selector, address(pair)));
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function test_addLiquidityWithReservoir_revertWhenReservoirAIsInsufficient(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 amountBDesired
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Rebasing tokenA up by 10% to create a reservoir of `reservoirA = poolA/10`
        tokenA.applyMultiplier(11, 10);
        // Ensuring that amountBDesired is <= 10% of poolB
        amountBDesired = bound(amountBDesired, 1, poolB / 10 - 1);

        // Making amountAMin > amountAOptimal so that the reservoirA is insufficient
        (, uint256 amountAOptimal) =
            ButtonswapV2Library.getMintSwappedAmounts(address(pair), address(tokenB), address(tokenA), amountBDesired);
        uint256 amountAMin = amountAOptimal + 1;

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = 0;
        addLiquidityParams.amountBDesired = amountBDesired;
        addLiquidityParams.amountAMin = amountAMin;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to addLiquidityWithReservoir to the pair
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector,
                address(tokenA),
                amountAOptimal,
                amountAMin
            )
        );
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function test_addLiquidityWithReservoir_revertWhenReservoirBIsInsufficient(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 amountADesired
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Rebasing tokenB up by 10% to create a reservoir of `reservoirB = poolB/10`
        tokenB.applyMultiplier(11, 10);
        // Ensuring that amountADesired is <= 10% of poolA
        amountADesired = bound(amountADesired, 1, poolA / 10 - 1);

        // Making amountBMin > amountBOptimal so that the reservoirB is insufficient
        (, uint256 amountBOptimal) =
            ButtonswapV2Library.getMintSwappedAmounts(address(pair), address(tokenA), address(tokenB), amountADesired);
        uint256 amountBMin = amountBOptimal + 1;

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = amountADesired;
        addLiquidityParams.amountBDesired = 0;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = amountBMin;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        // Attempting to addLiquidityWithReservoir to the pair
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.InsufficientTokenAmount.selector,
                address(tokenB),
                amountBOptimal,
                amountBMin
            )
        );
        genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);
    }

    function helper_estimateLiquidityOutWithReservoir(
        address pair,
        address tokenBAddress,
        address tokenAAddress,
        uint256 amountBDesired
    ) private view returns (uint256 liquidityOut) {
        uint256 poolA;
        uint256 poolB;
        uint256 reservoirA;
        // Getting reservoir size
        if (tokenAAddress < tokenBAddress) {
            (poolA, poolB, reservoirA,,,,) = IButtonswapV2Pair(pair).getLiquidityBalances();
        } else {
            (poolB, poolA,, reservoirA,,,) = IButtonswapV2Pair(pair).getLiquidityBalances();
        }

        uint256 tokenBToSwap;
        uint256 swappedReservoirAmountA;
        (tokenBToSwap, swappedReservoirAmountA) =
            ButtonswapV2Library.getMintSwappedAmounts(address(pair), tokenBAddress, tokenAAddress, amountBDesired);

        // Making sure poolA doesn't get Overflowed
        vm.assume(poolA + swappedReservoirAmountA < type(uint104).max);
        // Making sure poolB doesn't get Overflowed
        vm.assume(poolB + amountBDesired < type(uint104).max);
        // Making sure reservoirA is not exceeded
        vm.assume(swappedReservoirAmountA < reservoirA);
        // Making sure the rest of reservoirA can absorb the ephemeral sync that happens from the tokenBToSwap transfer-in
        vm.assume((poolB + amountBDesired) * poolA <= (poolA + reservoirA) * poolB);

        // Estimating how much liquidity will be minted
        liquidityOut = PairMath.getDualSidedMintLiquidityOutAmount(
            IButtonswapV2Pair(pair).totalSupply(),
            swappedReservoirAmountA,
            amountBDesired - tokenBToSwap,
            poolA + reservoirA - swappedReservoirAmountA,
            poolB + tokenBToSwap
        );

        // Making sure minimum liquidity requirement is met
        vm.assume(liquidityOut > 0);
        // Making sure swappableReservoirLimit is not exceeded
        vm.assume(swappedReservoirAmountA < IButtonswapV2Pair(pair).getSwappableReservoirLimit());
    }

    function test_addLiquidityWithReservoir_noHopsReservoirA(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountBDesired
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolA < (type(uint104).max / rebaseNumerator) * rebaseDenominator);

        // Rebasing tokenA positively up to create a tokenA reservoir
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Estimating how much of amountBDesired will be converted to A-tokens, and how much of the reservoir will be used
        uint256 liquidityOut =
            helper_estimateLiquidityOutWithReservoir(address(pair), address(tokenB), address(tokenA), amountBDesired);

        // Minting and approving enough tokenB to the router
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(genericButtonswapRouter), amountBDesired);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = 0;
        addLiquidityParams.amountBDesired = amountBDesired;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        //            address to = address(this);
        //            uint256 deadline = block.timestamp + 1000;

        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) =
            genericButtonswapRouter.addLiquidity(addLiquidityParams, address(this), block.timestamp + 1000);

        assertEq(amountsA.length, 0, "AmountsA should be empty since tokenA was untouched");
        assertEq(amountsB[0], amountBDesired, "AmountsB[0] should be amountBDesired");
        assertEq(liquidity, liquidityOut, "Liquidity should be equal to estimated liquidityOut");
    }

    function test_addLiquidityWithReservoir_noHopsReservoirB(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountADesired
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating A-B pair with at least minimum liquidity and poolA:poolB price ratio
        poolA = bound(poolA, 10000, type(uint104).max);
        poolB = bound(poolB, 10000, type(uint104).max);
        (IButtonswapV2Pair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolB < (type(uint104).max / rebaseNumerator) * rebaseDenominator);

        // Rebasing tokenB positively up to create a tokenB reservoir
        tokenB.applyMultiplier(rebaseNumerator, rebaseDenominator);

        uint256 liquidityOut =
            helper_estimateLiquidityOutWithReservoir(address(pair), address(tokenA), address(tokenB), amountADesired);

        // Minting and approving enough tokenA to the router
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(genericButtonswapRouter), amountADesired);

        // Creating the addLiquidityParams
        addLiquidityParams.operation = ButtonswapOperations.Liquidity.SINGLE;
        addLiquidityParams.tokenA = address(tokenA);
        addLiquidityParams.tokenB = address(tokenB);
        //        addLiquidityParams.swapStepsA; // Default to []
        //        addLiquidityParams.swapStepsB; // Default to []
        addLiquidityParams.amountADesired = amountADesired;
        addLiquidityParams.amountBDesired = 0;
        addLiquidityParams.amountAMin = 0;
        addLiquidityParams.amountBMin = 0;
        addLiquidityParams.liquidityMin = 0;
        addLiquidityParams.movingAveragePrice0ThresholdBps = 0;
        addLiquidityParams.createPair = false;
        addLiquidityParams.data = encodeV2Data(plBps, feeBps);
        address to = address(this);
        uint256 deadline = block.timestamp + 1000;

        (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) =
            genericButtonswapRouter.addLiquidity(addLiquidityParams, to, deadline);

        assertEq(amountsA[0], amountADesired, "AmountsA[0] should be amountADesired");
        assertEq(amountsB.length, 0, "AmountsB should be empty since tokenB was untouched");
        assertEq(liquidity, liquidityOut, "Liquidity should be equal to estimated liquidityOut");
    }
}
