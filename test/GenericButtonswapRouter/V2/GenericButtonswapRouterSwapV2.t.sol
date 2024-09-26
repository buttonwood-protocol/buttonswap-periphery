// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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
import {ButtonswapV2Factory} from "buttonswap-periphery_buttonswap-v2-core/ButtonswapV2Factory.sol";
import {IButtonswapV2Pair} from
    "buttonswap-periphery_buttonswap-v2-core/interfaces/IButtonswapV2Pair/IButtonswapV2Pair.sol";
import {ButtonswapV2FactoryHelper} from "buttonswap-periphery_buttonswap-v2-core/ButtonswapV2FactoryHelper.sol";
import {ButtonswapV2Library} from "../../../src/libraries/ButtonswapV2Library.sol";
import {IButtonswapV2Factory} from
    "buttonswap-periphery_buttonswap-v2-core/interfaces/IButtonswapV2Factory/IButtonswapV2Factory.sol";
import {Math} from "buttonswap-periphery_buttonswap-v2-core/libraries/Math.sol";

contract GenericButtonswapRouterSwapV2Test is Test, IGenericButtonswapRouterErrors {
    uint256 constant BPS = 10_000;
    uint8 constant V2 = 2;

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

    // Required function for receiving ETH refunds
    receive() external payable {}

    function setUp() public {
        (feeToSetter, feeToSetterPrivateKey) = makeAddrAndKey("feeToSetter");
        (isCreationRestrictedSetter, isCreationRestrictedSetterPrivateKey) =
            makeAddrAndKey("isCreationRestrictedSetter");
        (isPausedSetter, isPausedSetterPrivateKey) = makeAddrAndKey("isPausedSetter");
        (paramSetter, paramSetterPrivateKey) = makeAddrAndKey("paramSetter");
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        tokenA = new MockRebasingERC20("TokenA", "TKNA", 18, 1e36);
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18, 1e36);
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

    function test_factoryV2() public view {
        assertEq(genericButtonswapRouter.v2Factory(), address(buttonswapV2Factory));
    }

    //    function test_hello(uint8 version, uint16 plBps, uint16 feeBps) public {
    //        bytes memory wap = abi.encodePacked(version, plBps, feeBps);
    //
    //        (uint8 newVersion, uint16 newPlBps, uint16 newFeeBps) = ButtonswapV2Library.decodeData(wap);
    //
    //        assertEq(version, newVersion);
    //        assertEq(plBps, newPlBps);
    //        assertEq(feeBps, newFeeBps);
    //    }

    //****  swapExactTokensForTokens ****//
    function test_swapExactTokensForTokens_singleSwapV2WithInsufficientOutputAmount(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 amountIn
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint88).max - 1000);
        poolB = bound(poolB, 10000, type(uint88).max);

        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountIn = bound(amountIn, 1000, Math.min(10000, type(uint88).max - poolA));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Estimating how much output a trade would give and making amountOutMin +1 higher
        // Also ensuring that expectedAmountOut is nonZero (otherwise the ButtonswapPair reverts with `InsufficientOutputAmount()` error)
        uint256 expectedAmountOut = ButtonswapV2Library.getAmountOut(amountIn, poolA, poolB, plBps, feeBps);
        vm.assume(expectedAmountOut > 0);
        uint256 amountOutMin = expectedAmountOut + 1;

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        bytes memory data = abi.encodePacked(V2, plBps, feeBps);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.SWAP, address(tokenB), data);

        // Approving the router to take at most amountIn tokenA
        tokenA.mint(address(this), amountIn);
        tokenA.approve(address(genericButtonswapRouter), amountIn);

        // Attempting to do a simple swap
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.InsufficientOutputAmount.selector, amountOutMin, expectedAmountOut
            )
        );
        genericButtonswapRouter.swapExactTokensForTokens(
            address(tokenA), amountIn, amountOutMin, swapSteps, address(this), block.timestamp + 1
        );
    }

    function test_swapExactTokensForTokens_singleSwapV2(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 amountIn,
        uint256 amountOutMin
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint88).max - 1000);
        poolB = bound(poolB, 10000, type(uint88).max);

        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountIn = bound(amountIn, 1000, Math.min(10000, type(uint88).max - poolA));

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Estimating how much output a trade would give
        uint256 expectedAmountOut = ButtonswapV2Library.getAmountOut(amountIn, poolA, poolB, plBps, feeBps);
        // Making sure that expectedAmountOut is positive
        vm.assume(expectedAmountOut > 0);
        // Ensuring amountOutMin bounded below expectedAmountOut
        amountOutMin = bound(amountOutMin, 0, expectedAmountOut);

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        bytes memory data = abi.encodePacked(V2, plBps, feeBps);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.SWAP, address(tokenB), data);

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

    //**** swapTokensForExactTokens ****//

    function test_swapTokensForExactTokens_singleSwapV2WithExcessiveInputAmount(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 amountOut
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint88).max - 1000);
        poolB = bound(poolB, 10000, type(uint88).max);

        // Ensuring that amountOut is bounded to avoid errors/overflows/underflows
        amountOut = bound(amountOut, 1000, poolB - 1);

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Estimating how much input a trade would take and making amountInMax -1 lower
        uint256 expectedAmountIn = ButtonswapV2Library.getAmountIn(amountOut, poolA, poolB, plBps, feeBps);
        uint256 amountInMax = expectedAmountIn - 1;
        vm.assume(amountInMax < tokenA.mintableBalance());

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        bytes memory data = abi.encodePacked(V2, plBps, feeBps);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.SWAP, address(tokenB), data);

        // Approving the router to take at most amountInMax tokenA
        tokenA.mint(address(this), amountInMax);
        tokenA.approve(address(genericButtonswapRouter), amountInMax);

        // Attempting to do a simple swap
        vm.expectRevert(
            abi.encodeWithSelector(
                IGenericButtonswapRouterErrors.ExcessiveInputAmount.selector, amountInMax, expectedAmountIn
            )
        );
        genericButtonswapRouter.swapTokensForExactTokens(
            address(tokenA), amountOut, amountInMax, swapSteps, address(this), block.timestamp + 1
        );
    }

    function test_swapTokensForExactTokens_singleSwapV2(
        uint256 poolA,
        uint256 poolB,
        uint16 plBps,
        uint16 feeBps,
        uint256 amountOut,
        uint256 amountInMax
    ) public {
        // Ensuring plBps and feeBps are within bounds
        plBps = uint16(bound(plBps, 0, BPS - 30));
        feeBps = uint16(bound(feeBps, defaultPairCreationParameters.protocolFeeMbps, BPS - 1));

        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint88).max - 1000);
        poolB = bound(poolB, 10000, type(uint88).max);

        // Ensuring that amountOut is bounded to avoid errors/overflows/underflows
        amountOut = bound(amountOut, 1000, poolB - 1);

        // Allow the factory to create pairs with the given parameters
        setupButtonswapV2FactoryParameters(plBps, feeBps);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB, plBps, feeBps);

        // Estimating how much input a trade would take
        uint256 expectedAmountIn = ButtonswapV2Library.getAmountIn(amountOut, poolA, poolB, plBps, feeBps);
        // Making sure that expectedAmountIn is positive but not outside of possible range
        vm.assume(expectedAmountIn > 0);
        vm.assume(expectedAmountIn < type(uint88).max - poolA);
        // Ensuring amountInMax bounded above expectedAmountIn
        amountInMax = bound(amountInMax, expectedAmountIn, tokenA.mintableBalance());

        // Creating swapSteps for single swap
        IGenericButtonswapRouter.SwapStep[] memory swapSteps = new IGenericButtonswapRouter.SwapStep[](1);
        bytes memory data = abi.encodePacked(V2, plBps, feeBps);
        swapSteps[0] = IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.SWAP, address(tokenB), data);

        // Approving the router to take at most amountInMax tokenA
        tokenA.mint(address(this), amountInMax);
        tokenA.approve(address(genericButtonswapRouter), amountInMax);

        // Doing a single swap
        uint256[] memory amounts = genericButtonswapRouter.swapTokensForExactTokens(
            address(tokenA), amountOut, amountInMax, swapSteps, address(this), block.timestamp + 1
        );

        // Validating the correct amounts
        assertEq(amounts[0], expectedAmountIn, "First amount should be expectedAmountIn");
        // Need to use `Ge()` instead of `Eq()`.
        // On this test, there is no extraneous input, but precision loss of uint112s can cause: getAmountOut(getAmountIn(amountOut)) > amountOut
        // Thus the amount received will actually be greater than or equal to amountOut
        assertGe(amounts[1], amountOut, "Last amount should be [AT LEAST] amountOut");
    }
}
