// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IButtonswapFactory} from
"buttonswap-periphery_buttonswap-core/interfaces/IButtonswapFactory/IButtonswapFactory.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IGenericButtonswapRouter} from "./interfaces/IButtonswapRouter/IGenericButtonswapRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IButtonToken} from "./interfaces/IButtonToken.sol";
import {ButtonswapLibrary} from "./libraries/ButtonswapLibrary.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {ButtonswapOperations} from "./libraries/ButtonswapOperations.sol";
import {Math} from "./libraries/Math.sol";
import {console} from "buttonswap-periphery_forge-std/console.sol";

contract GenericButtonswapRouter is IGenericButtonswapRouter {
    uint256 private constant BPS = 10_000;

    /**
     * @inheritdoc IGenericButtonswapRouter
     */
    address public immutable override factory;
    /**
     * @inheritdoc IGenericButtonswapRouter
     */
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) {
            revert Expired(deadline, block.timestamp);
        }
        _;
    }

    /**
     * @dev Only accepts ETH via fallback from the WETH contract
     */
    receive() external payable {
        if (msg.sender != WETH) {
            revert NonWETHSender(msg.sender);
        }
    }

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    // **** TransformOperations **** //

    // Swap
    function _swap(address tokenIn, address tokenOut, uint256 amountIn) internal virtual returns (uint256 amountOut) {
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, tokenIn, tokenOut));

        (uint256 poolIn, uint256 poolOut) = ButtonswapLibrary.getPools(factory, tokenIn, tokenOut);
        amountOut = ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut);

        TransferHelper.safeApprove(tokenIn, address(pair), amountIn);
        if (tokenIn < tokenOut) {
            pair.swap(amountIn, 0, 0, amountOut, address(this));
        } else {
            pair.swap(0, amountIn, amountOut, 0, address(this));
        }
    }

    // Wrap-Button
    function _wrapButton(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        virtual
        returns (uint256 amountOut)
    {
        if (IButtonToken(tokenOut).underlying() != tokenIn) {
            // ToDo: Remove check?
            revert IncorrectButtonUnderlying(tokenOut, IButtonToken(tokenOut).underlying(), tokenIn);
        }
        // ToDo: Maybe approve/deposit the entire balance?
        TransferHelper.safeApprove(tokenIn, tokenOut, amountIn);
        amountOut = IButtonToken(tokenOut).deposit(amountIn);
    }

    // Unwrap-Button
    function _unwrapButton(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        virtual
        returns (uint256 amountOut)
    {
        if (IButtonToken(tokenIn).underlying() != tokenOut) {
            // ToDo: Remove check?
            revert IncorrectButtonUnderlying(tokenIn, IButtonToken(tokenIn).underlying(), tokenOut);
        }
        if (IERC20(tokenIn).balanceOf(address(this)) != amountIn) {
            // ToDo: Remove check?
            revert IncorrectBalance(tokenIn, IERC20(tokenIn).balanceOf(address(this)), amountIn);
        }
        // ToDo: Maybe withdraw the entire balance?
        amountOut = IButtonToken(tokenIn).burnAll();
    }

    // Wrap-WETH
    function _wrapWETH(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        virtual
        returns (uint256 amountOut)
    {
        if (tokenIn != address(0)) {
            revert NonEthToken(tokenIn);
        }
        if (tokenOut != address(WETH)) {
            revert NonWethToken(WETH, tokenOut);
        }
        // ToDo: No need for this check. Always transfer entire router balance
        //        if (amountIn != address(this).balance) {
        //            // ToDo: Remove check? Maybe just deposit the entire balance of the router so it's always empty.
        //            revert IncorrectBalance();
        //        }
        IWETH(WETH).deposit{value: amountIn}();
        amountOut = IERC20(WETH).balanceOf(address(this));
    }

    // Unwrap-WETH
    function _unwrapWETH(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        virtual
        returns (uint256 amountOut)
    {
        if (tokenIn != address(WETH)) {
            revert NonWethToken(WETH, tokenIn);
        }
        if (tokenOut != address(0)) {
            revert NonEthToken(tokenOut);
        }
        IWETH(WETH).withdraw(amountIn); // ToDo: Maybe just withdraw the entire balance?
        amountOut = address(this).balance;
    }

    function _swapStep(address tokenIn, uint256 amountIn, SwapStep calldata swapStep)
        internal
        virtual
        returns (address tokenOut, uint256 amountOut)
    {
        tokenOut = swapStep.tokenOut;
        if (swapStep.operation == ButtonswapOperations.Swap.SWAP) {
            amountOut = _swap(tokenIn, tokenOut, amountIn);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_BUTTON) {
            amountOut = _wrapButton(tokenIn, tokenOut, amountIn);
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_BUTTON) {
            amountOut = _unwrapButton(tokenIn, tokenOut, amountIn);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_WETH) {
            amountOut = _wrapWETH(tokenIn, tokenOut, amountIn);
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_WETH) {
            amountOut = _unwrapWETH(tokenIn, tokenOut, amountIn);
        }
    }

    // ToDo: Encapsulating the swap logic into a separate internal function
    function _swapExactTokensForTokens(
        address tokenIn,
        uint256 amountIn,
        SwapStep[] calldata swapSteps
    ) internal returns (uint256[] memory amounts, address tokenOut, uint256 amountOut) {
        tokenOut = tokenIn;
        amountOut = amountIn;
        amounts = new uint256[](swapSteps.length + 1);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < swapSteps.length; i++) {
            (tokenOut, amountOut) = _swapStep(tokenIn, amountIn, swapSteps[i]);
            amounts[i + 1] = amountOut;
        }
    }

    // **** External Functions **** //
    function swapExactTokensForTokens(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        SwapStep[] calldata swapSteps,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256[] memory amounts) {
        // Transferring in the initial amount if the first swapStep is not wrap-weth
        if (swapSteps[0].operation != ButtonswapOperations.Swap.WRAP_WETH) {
            TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        }

        // Doing the swaps one-by-one and re-using tokenIn/amountIn as tokenOut/amountOut
        (amounts, tokenIn, amountIn) = _swapExactTokensForTokens(tokenIn, amountIn, swapSteps);

        // Confirm that the final amountOut is greater than or equal to the amountOutMin
        if (amountIn < amountOutMin) {
            revert InsufficientOutputAmount(amountOutMin, amountIn);
        }

        // Transferring out final amount if the last swapStep is not unwrap-weth
        if (swapSteps[swapSteps.length - 1].operation != ButtonswapOperations.Swap.UNWRAP_WETH) {
            TransferHelper.safeTransfer(tokenIn, to, amountIn);
        } else {
            payable(to).transfer(amountIn);
        }
    }

    // ToDo: Potentially move into it's own library
    function _getAmountIn(address tokenIn, uint256 amountOut, SwapStep calldata swapStep)
        internal
        virtual
        returns (uint256 amountIn)
    {
        if (swapStep.operation == ButtonswapOperations.Swap.SWAP) {
            (uint256 poolIn, uint256 poolOut) = ButtonswapLibrary.getPools(factory, tokenIn, swapStep.tokenOut);
            amountIn = ButtonswapLibrary.getAmountIn(amountOut, poolIn, poolOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_BUTTON) {
            amountIn = IButtonToken(swapStep.tokenOut).wrapperToUnderlying(amountOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_BUTTON) {
            amountIn = IButtonToken(tokenIn).underlyingToWrapper(amountOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_WETH) {
            amountIn = amountOut;
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_WETH) {
            amountIn = amountOut;
        }
    }

    // ToDo: Potentially move into it's own library
    function _getAmountIn(address tokenIn, uint256 amountOut, SwapStep[] calldata swapSteps)
    internal
    virtual
    returns (uint256 amountIn)
    {
        amountIn = amountOut;
        if (swapSteps.length > 0) {
            for (uint256 i = swapSteps.length - 1; i > 0; i--) {
                amountIn = _getAmountIn(swapSteps[i-1].tokenOut, amountIn, swapSteps[i]);
            }
            // Do the last iteration outside of the loop since we need to use tokenIn
            amountIn = _getAmountIn(tokenIn, amountIn, swapSteps[0]);
        }
    }

    // ToDo: Potentially move into it's own library
    function _getAmountsIn(address firstTokenIn, uint256 amountOut, SwapStep[] calldata swapSteps)
        internal
        virtual
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](swapSteps.length + 1);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = amounts.length - 2; i > 1; i--) {
            // ToDo: Fix the fact that this isn't updating any array values in amounts
            amountOut = _getAmountIn(swapSteps[i - 1].tokenOut, amountOut, swapSteps[i]);
        }
        amounts[0] = _getAmountIn(firstTokenIn, amountOut, swapSteps[0]);
    }

    // ToDo: Standardize with amountIn-functions and potentially move into it's own library
    function _getAmountOut(address tokenIn, uint256 amountIn, SwapStep calldata swapStep) internal virtual returns (uint256 amountOut) {
        if (swapStep.operation == ButtonswapOperations.Swap.SWAP) {
            (uint256 poolIn, uint256 poolOut) = ButtonswapLibrary.getPools(factory, tokenIn, swapStep.tokenOut);
            amountOut = ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_BUTTON) {
            amountOut = IButtonToken(swapStep.tokenOut).underlyingToWrapper(amountIn);
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_BUTTON) {
            amountOut = IButtonToken(tokenIn).wrapperToUnderlying(amountIn);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_WETH) {
            amountOut = amountIn;
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_WETH) {
            amountOut = amountIn;
        }
    }

    // ToDo: Standardize with amountIn-functions and potentially move into it's own library
    function _getAmountOut(address tokenIn, uint256 amountIn, SwapStep[] calldata swapSteps) internal virtual returns (uint256 amountOut) {
        amountOut = amountIn;
        for (uint256 i=0; i < swapSteps.length; i++) {
            amountOut = _getAmountOut(tokenIn, amountOut, swapSteps[i]);
        }
    }

    function swapTokensForExactTokens(
        address tokenIn,
        uint256 amountOut,
        uint256 amountInMax,
        SwapStep[] calldata swapSteps,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = _getAmountsIn(tokenIn, amountOut, swapSteps);
        if (amounts[0] > amountInMax) {
            revert ExcessiveInputAmount(amountInMax, amounts[0]);
        }
        // Transferring in the initial amount if the first swapStep is not wrap-weth
        if (swapSteps[0].operation != ButtonswapOperations.Swap.WRAP_WETH) {
            TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amounts[0]);
        }

        for (uint256 i = 0; i < swapSteps.length; i++) {
            (tokenIn, amountOut) = _swapStep(tokenIn, amounts[i], swapSteps[i]);
            if (amountOut < amounts[i + 1]) {
                // ToDo: Consider using a different error for better clarity. This might not even be a necessary error
                revert InsufficientOutputAmount(amounts[i + 1], amountOut);
            }
        }
        // Transferring out final amount if the last swapStep is not unwrap-weth
        // The final value of amountIn is the last amountOut from the last _swapStep execution
        if (swapSteps[swapSteps.length - 1].operation != ButtonswapOperations.Swap.UNWRAP_WETH) {
            TransferHelper.safeTransfer(tokenIn, to, amountOut);
        } else {
            payable(to).transfer(amountOut);
        }
    }

    function _addLiquidityGetOrCreatePair(AddLiquidityStep calldata addLiquidityStep) internal returns (address pair, bool aToken0) {
        // No need to validate if finalTokenA or finalTokenB are address(0) since getPair and createPair will handle it
        address pairTokenA = addLiquidityStep.swapStepsA.length > 0 ? addLiquidityStep.swapStepsA[addLiquidityStep.swapStepsA.length - 1].tokenOut : addLiquidityStep.tokenA;
        address pairTokenB = addLiquidityStep.swapStepsB.length > 0 ? addLiquidityStep.swapStepsB[addLiquidityStep.swapStepsB.length - 1].tokenOut : addLiquidityStep.tokenB;

        // Return a boolean indicating if pairTokenA is token0
        aToken0 = pairTokenA < pairTokenB;

        // create the pair if it doesn't exist yet
        pair = IButtonswapFactory(factory).getPair(pairTokenA, pairTokenB);
        if (pair == address(0)) {
            pair = IButtonswapFactory(factory).createPair(pairTokenA, pairTokenB);
        }
    }

    function _validateMovingAveragePrice0Threshold(
        AddLiquidityStep calldata addLiquidityStep,
        uint256 poolA,
        uint256 poolB,
        address pair
    ) internal {
        address pairTokenA = addLiquidityStep.swapStepsA.length > 0 ? addLiquidityStep.swapStepsA[addLiquidityStep.swapStepsA.length - 1].tokenOut : addLiquidityStep.tokenA;
        address pairTokenB = addLiquidityStep.swapStepsB.length > 0 ? addLiquidityStep.swapStepsB[addLiquidityStep.swapStepsB.length - 1].tokenOut : addLiquidityStep.tokenB;

        // Validate that the moving average price is within the threshold for pairs that exist
        if (poolA > 0 && poolB > 0) {
            uint256 movingAveragePrice0 = IButtonswapPair(pair).movingAveragePrice0();
            if (pairTokenA < pairTokenB) {
                // pairTokenA is token0
                uint256 cachedTerm = Math.mulDiv(movingAveragePrice0, poolA * BPS, 2 ** 112);
                if (
                    poolB * (BPS - addLiquidityStep.movingAveragePrice0ThresholdBps) > cachedTerm
                    || poolB * (BPS + addLiquidityStep.movingAveragePrice0ThresholdBps) < cachedTerm
                ) {
                    revert MovingAveragePriceOutOfBounds(poolA, poolB, movingAveragePrice0, addLiquidityStep.movingAveragePrice0ThresholdBps);
                }
            } else {
                // pairTokenB is token0
                uint256 cachedTerm = Math.mulDiv(movingAveragePrice0, poolB * BPS, 2 ** 112);
                if (
                    poolA * (BPS - addLiquidityStep.movingAveragePrice0ThresholdBps) > cachedTerm
                    || poolA * (BPS + addLiquidityStep.movingAveragePrice0ThresholdBps) < cachedTerm
                ) {
                    revert MovingAveragePriceOutOfBounds(poolB, poolA, movingAveragePrice0, addLiquidityStep.movingAveragePrice0ThresholdBps);
                }
            }
        }
    }

    function _addLiquidityDual(
        AddLiquidityStep calldata addLiquidityStep,
        address pair,
        bool aToken0
    ) internal returns (uint256 amountA, uint256 amountB) {
        // Fetch pair liquidity
        uint256 poolA; uint256 poolB; uint256 reservoirA; uint256 reservoirB;
        if (aToken0) {
            (poolA,poolB,reservoirA,reservoirB,) = IButtonswapPair(pair).getLiquidityBalances();
        } else {
            (poolB,poolA,reservoirB,reservoirA,) = IButtonswapPair(pair).getLiquidityBalances();
        }

        // If pair has no liquidity, then deposit addLiquidityStep.amountADesired and addLiquidityStep.amountBDesired
        if ((poolA + reservoirA) == 0 && (poolB + reservoirB) == 0) {
            (amountA, amountB) = (addLiquidityStep.amountADesired, addLiquidityStep.amountBDesired);
        } else {
            // Calculate optimal amountB and check if it fits
            uint256 amountOptimal =
                _getAmountIn(
                    addLiquidityStep.tokenB,
                    ButtonswapLibrary.quote(
                        _getAmountOut(addLiquidityStep.tokenA, addLiquidityStep.amountADesired, addLiquidityStep.swapStepsA),
                        poolA + reservoirA,
                        poolB + reservoirB
                    ),
                    addLiquidityStep.swapStepsB
                );
            if (amountOptimal <= addLiquidityStep.amountBDesired) {
                if (amountOptimal < addLiquidityStep.amountBMin) {
                    revert InsufficientTokenAmount(addLiquidityStep.tokenB, addLiquidityStep.amountBDesired, amountOptimal);
                }
                (amountA, amountB) = (addLiquidityStep.amountADesired, amountOptimal);
            } else {
                // Calculate optimal amountA (re-using variable) and check if it fits
                amountOptimal =
                    _getAmountIn(
                        addLiquidityStep.tokenA,
                        ButtonswapLibrary.quote(
                            _getAmountOut(addLiquidityStep.tokenB, addLiquidityStep.amountBDesired, addLiquidityStep.swapStepsB),
                            poolB + reservoirB,
                            poolA + reservoirA
                        ),
                        addLiquidityStep.swapStepsA
                    );
                assert(amountOptimal <= addLiquidityStep.amountADesired); //ToDo: Consider replacing with an error instead of an assert
                if (amountOptimal < addLiquidityStep.amountAMin) {
                    revert InsufficientTokenAmount(addLiquidityStep.tokenA, addLiquidityStep.amountADesired, amountOptimal);
                }
                (amountA, amountB) = (amountOptimal, addLiquidityStep.amountBDesired);
            }
        }

        // Validate that the moving average price is within the threshold for pairs that already existed
        _validateMovingAveragePrice0Threshold(
            addLiquidityStep,
            poolA,
            poolB,
            pair
        );
    }

    function addLiquidityDual(
        AddLiquidityStep calldata addLiquidityStep,
        address to,
        uint256 deadline //ToDo: Ensure the deadline
    ) internal returns (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) {
        // Create the pair if it doesn't exist yet
        (address pair, bool aToken0) = _addLiquidityGetOrCreatePair(addLiquidityStep);

        // Calculating how much of tokenA and tokenB to take from user
        (uint256 amountA, uint256 amountB) = _addLiquidityDual(addLiquidityStep, pair, aToken0);

        // ToDo: Take this code block and re-use as internal function?
        address tokenA = addLiquidityStep.tokenA;
        address tokenB = addLiquidityStep.tokenB;
        // Transferring in tokenA from user if first swapStepsA is not wrap-weth
        if (addLiquidityStep.swapStepsA.length == 0 || addLiquidityStep.swapStepsA[0].operation != ButtonswapOperations.Swap.WRAP_WETH) {
            TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        }
        // Transferring in tokenB from user if first swapStepsB is not wrap-weth
        if (addLiquidityStep.swapStepsB.length == 0 || addLiquidityStep.swapStepsB[0].operation != ButtonswapOperations.Swap.WRAP_WETH) {
            TransferHelper.safeTransferFrom(tokenB, msg.sender, address(this), amountB);
        }

        // Reusing tokenA/amountA as finalTokenA/finalAmountA and likewise for tokenB
        (amountsA,tokenA,amountA) = _swapExactTokensForTokens(tokenA, amountA, addLiquidityStep.swapStepsA);
        (amountsB,tokenB,amountB) = _swapExactTokensForTokens(tokenB, amountB, addLiquidityStep.swapStepsB);
        // ToDo: Up to here

        // Approving final tokenA for transfer to pair
        TransferHelper.safeApprove(tokenA, pair, amountA);
        // Approving final tokenB for transfer to pair
        TransferHelper.safeApprove(tokenB, pair, amountB);

        if (tokenA < tokenB) { // ToDo: replace with aToken0
            liquidity = IButtonswapPair(pair).mint(amountA, amountB, to);
        } else {
            liquidity = IButtonswapPair(pair).mint(amountB, amountA, to);
        }
    }

    // ToDo: Consolidate with _addLiquidityGetOrCreatePair
    function _addLiquidityGetPair(AddLiquidityStep calldata addLiquidityStep) internal view returns (address pair, bool aToken0) {
        // No need to validate if finalTokenA or finalTokenB are address(0) since getPair and createPair will handle it
        address pairTokenA = addLiquidityStep.swapStepsA.length > 0 ? addLiquidityStep.swapStepsA[addLiquidityStep.swapStepsA.length - 1].tokenOut : addLiquidityStep.tokenA;
        address pairTokenB = addLiquidityStep.swapStepsB.length > 0 ? addLiquidityStep.swapStepsB[addLiquidityStep.swapStepsB.length - 1].tokenOut : addLiquidityStep.tokenB;

        // Return a boolean indicating if pairTokenA is token0
        aToken0 = pairTokenA < pairTokenB;

        // Fetch pair from the factory
        pair = IButtonswapFactory(factory).getPair(pairTokenA, pairTokenB);

        // Revert if the pair does not exist
        if (pair == address(0)) {
            revert PairDoesNotExist(pairTokenA, pairTokenB);
        }
    }

    function _addLiquidityGetMintSwappedAmounts(
        AddLiquidityStep calldata addLiquidityStep,
        address pair,
        bool aToken0,
        bool isReservoirA
    ) internal returns (uint256 amountA, uint256 amountB) {
        // ToDo: Figure out how to get these ahead of time rather than here
        address pairTokenA; address pairTokenB;
        if (aToken0) {
            pairTokenA = IButtonswapPair(pair).token0();
            pairTokenB = IButtonswapPair(pair).token1();
        } else {
            pairTokenA = IButtonswapPair(pair).token1();
            pairTokenB = IButtonswapPair(pair).token0();
        }

        // ReservoirA is non-empty
        if (isReservoirA) {
            // we take from reservoirA and the user-provided amountBDesired
            // But modify so that you don't do liquidityOut logic since you don't need it
            (, uint256 amountAOptimal) =
                                ButtonswapLibrary.getMintSwappedAmounts(
                    factory,
                    pairTokenB,
                    pairTokenA,
                    _getAmountOut(addLiquidityStep.tokenB, addLiquidityStep.amountBDesired, addLiquidityStep.swapStepsB)
                );
            amountAOptimal = _getAmountIn(addLiquidityStep.tokenA, amountAOptimal, addLiquidityStep.swapStepsA);
            // Slippage-check: User wants to drain from the res by amountAMin or more
            if (amountAOptimal < addLiquidityStep.amountAMin) {
                revert InsufficientTokenAmount(addLiquidityStep.tokenA, amountAOptimal, addLiquidityStep.amountAMin);
            }
            (amountA, amountB) = (0, addLiquidityStep.amountBDesired);
        } else { // ReservoirB is non-empty
            // we take from reservoirB and the user-provided amountADesired
            (, uint256 amountBOptimal) =
                                ButtonswapLibrary.getMintSwappedAmounts(
                    factory,
                    pairTokenA,
                    pairTokenB,
                    _getAmountOut(addLiquidityStep.tokenA, addLiquidityStep.amountADesired, addLiquidityStep.swapStepsA)
                );
            amountBOptimal = _getAmountIn(addLiquidityStep.tokenB, amountBOptimal, addLiquidityStep.swapStepsB);
            // Slippage-check: User wants to drain from the res by amountBMin or more
            if (amountBOptimal < addLiquidityStep.amountBMin) {
                revert InsufficientTokenAmount(addLiquidityStep.tokenB, amountBOptimal, addLiquidityStep.amountBMin);
            }
            (amountA, amountB) = (addLiquidityStep.amountADesired, 0);
        }
    }

    function _addLiquidityWithReservoir(
        AddLiquidityStep calldata addLiquidityStep,
        address pair,
        bool aToken0
    ) internal returns (uint256 amountA, uint256 amountB) {

        // Fetch pair liquidity
        uint256 poolA; uint256 poolB; uint256 reservoirA; uint256 reservoirB;
        if (aToken0) {
            (poolA,poolB,reservoirA,reservoirB,) = IButtonswapPair(pair).getLiquidityBalances();
        } else {
            (poolB,poolA,reservoirB,reservoirA,) = IButtonswapPair(pair).getLiquidityBalances();
        }

        // If poolA and poolB are both 0, then the pair hasn't been initialized yet
        if (poolA == 0 || poolB == 0) {
            revert NotInitialized();
        }
        // If reservoirA and reservoirB are both 0, then the pair doesn't have a non-empty reservoir
        if (reservoirA == 0 && reservoirB == 0) {
            revert NoReservoir();
        }

        (amountA, amountB) = _addLiquidityGetMintSwappedAmounts(
            addLiquidityStep,
            pair,
            aToken0,
            reservoirA > 0
        );
    }

    function addLiquidityWithReservoir(
        AddLiquidityStep calldata addLiquidityStep,
        address to,
        uint256 deadline //ToDo: Ensure the deadline
    ) internal returns (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) {
        // Fetch pair from factory
        (address pair, bool aToken0) = _addLiquidityGetPair(addLiquidityStep);

        // Calculating how much of tokenA and tokenB to take from user
        (uint256 amountA, uint256 amountB) = _addLiquidityWithReservoir(addLiquidityStep, pair, aToken0);

        if (amountA > 0) {
            address tokenA = addLiquidityStep.tokenA;
            // Transferring in tokenA from user if first swapStepsA is not wrap-weth
            if (addLiquidityStep.swapStepsA.length == 0 || addLiquidityStep.swapStepsA[0].operation != ButtonswapOperations.Swap.WRAP_WETH) {
                TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), amountA);
            }
            // Reusing tokenA/amountA as finalTokenA/finalAmountA
            (amountsA,tokenA,amountA) = _swapExactTokensForTokens(tokenA, amountA, addLiquidityStep.swapStepsA);

            // Approving final tokenA for transfer to pair
            TransferHelper.safeApprove(tokenA, pair, amountA);
            liquidity = IButtonswapPair(pair).mintWithReservoir(amountA, to);
        } else if (amountB > 0) {
            (,, uint112 res0, uint112 res1,) = IButtonswapPair(pair).getLiquidityBalances();
            address tokenB = addLiquidityStep.tokenB;
            // Transferring in tokenB from user if first swapStepsB is not wrap-weth
            if (addLiquidityStep.swapStepsB.length == 0 || addLiquidityStep.swapStepsB[0].operation != ButtonswapOperations.Swap.WRAP_WETH) {
                TransferHelper.safeTransferFrom(tokenB, msg.sender, address(this), amountB);
            }
            // Reusing tokenB/amountB as finalTokenB/finalAmountB
            (amountsB,tokenB,amountB) = _swapExactTokensForTokens(tokenB, amountB, addLiquidityStep.swapStepsB);
            // Approving final tokenB for transfer to pair
            TransferHelper.safeApprove(tokenB, pair, amountB);
            liquidity = IButtonswapPair(pair).mintWithReservoir(amountB, to);
        }
    }

    function addLiquidity(
        AddLiquidityStep calldata addLiquidityStep,
        address to,
        uint256 deadline //ToDo: Ensure the deadline
    ) external payable returns (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) {
        if (addLiquidityStep.operation == ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY) {
            return addLiquidityDual(addLiquidityStep, to, deadline);
        } else if (addLiquidityStep.operation == ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY_WITH_RESERVOIR) {
            return addLiquidityWithReservoir(addLiquidityStep, to, deadline);
        }

    }

    function removeLiquidity(
        RemoveLiquidityStep calldata removeLiquidityStep,
        SwapStep[] calldata swapStepsA,
        SwapStep[] calldata swapStepsB,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {}

    // ToDo: addLiquidity
    // ToDo: addLiquidityWithReservoir
    // ToDo: removeLiquidity
    // ToDo: removeLiquidityFromReservoir
}
