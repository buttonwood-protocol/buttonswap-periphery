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
import {IUSDM} from "./interfaces/IUSDM.sol";
import {ButtonswapV2Library} from "./libraries/ButtonswapV2Library.sol";
import {IButtonswapV2Pair} from
    "buttonswap-periphery_buttonswap-v2-core/interfaces/IButtonswapV2Pair/IButtonswapV2Pair.sol";
import {IButtonswapV2Factory} from
    "buttonswap-periphery_buttonswap-v2-core/interfaces/IButtonswapV2Factory/IButtonswapV2Factory.sol";

contract GenericButtonswapRouter is IGenericButtonswapRouter {
    uint256 private constant BPS = 10_000;

    /**
     * @inheritdoc IGenericButtonswapRouter
     */
    address public immutable override factory;

    /**
     * @inheritdoc IGenericButtonswapRouter
     */
    address public immutable override v2Factory;
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

    constructor(address _factory, address _v2Factory, address _WETH) {
        factory = _factory;
        v2Factory = _v2Factory;
        WETH = _WETH;
    }

    // **** TransformOperations **** //

    // Swap
    function _swap(address tokenIn, address tokenOut, bytes calldata data) internal returns (uint256 amountOut) {
        (uint8 version, uint16 plBps, uint16 feeBps) = ButtonswapV2Library.decodeData(data);
        if (version == 1) {
            amountOut = _swapV1(tokenIn, tokenOut);
        } else if (version == 2) {
            amountOut = _swapV2(tokenIn, tokenOut, plBps, feeBps);
        }
    }

    // SwapV1
    function _swapV1(address tokenIn, address tokenOut) internal returns (uint256 amountOut) {
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, tokenIn, tokenOut));
        uint256 amountIn = IERC20(tokenIn).balanceOf(address(this));

        (uint256 poolIn, uint256 poolOut) = ButtonswapLibrary.getPools(factory, tokenIn, tokenOut);
        amountOut = ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut);

        TransferHelper.safeApprove(tokenIn, address(pair), amountIn);
        if (tokenIn < tokenOut) {
            pair.swap(amountIn, 0, 0, amountOut, address(this));
        } else {
            pair.swap(0, amountIn, amountOut, 0, address(this));
        }
    }

    // SwapV2
    function _swapV2(address tokenIn, address tokenOut, uint16 plBps, uint16 feeBps)
        internal
        returns (uint256 amountOut)
    {
        IButtonswapV2Pair pair =
            IButtonswapV2Pair(ButtonswapV2Library.pairFor(v2Factory, tokenIn, tokenOut, plBps, feeBps));
        uint256 amountIn = IERC20(tokenIn).balanceOf(address(this));

        (uint256 poolIn, uint256 poolOut) = ButtonswapV2Library.getPoolsFromPair(address(pair), tokenIn, tokenOut);
        amountOut = ButtonswapV2Library.getAmountOut(amountIn, poolIn, poolOut, plBps, feeBps);

        TransferHelper.safeApprove(tokenIn, address(pair), amountIn);
        if (tokenIn < tokenOut) {
            pair.swap(amountIn, 0, 0, amountOut, address(this));
        } else {
            pair.swap(0, amountIn, amountOut, 0, address(this));
        }
    }

    // Wrap-Button
    function _wrapButton(address tokenIn, address tokenOut) internal returns (uint256 amountOut) {
        if (IButtonToken(tokenOut).underlying() != tokenIn) {
            revert IncorrectButtonPairing(tokenIn, tokenOut);
        }
        // Approving/depositing the entire balance of the router
        uint256 amountIn = IERC20(tokenIn).balanceOf(address(this));
        TransferHelper.safeApprove(tokenIn, tokenOut, amountIn);
        amountOut = IButtonToken(tokenOut).deposit(amountIn);
    }

    // Unwrap-Button
    function _unwrapButton(address tokenIn, address tokenOut) internal returns (uint256 amountOut) {
        if (IButtonToken(tokenIn).underlying() != tokenOut) {
            revert IncorrectButtonPairing(tokenOut, tokenIn);
        }
        // Burning the entire balance of the router
        amountOut = IButtonToken(tokenIn).burnAll();
    }

    // Wrap-WETH
    function _wrapWETH(address tokenIn, address tokenOut) internal returns (uint256 amountOut) {
        if (tokenIn != address(0)) {
            revert NonEthToken(tokenIn);
        }
        if (tokenOut != address(WETH)) {
            revert NonWethToken(WETH, tokenOut);
        }
        // Depositing the entire balance of the router
        uint256 amountIn = address(this).balance;
        IWETH(WETH).deposit{value: amountIn}();
        amountOut = amountIn;
    }

    // Unwrap-WETH
    function _unwrapWETH(address tokenIn, address tokenOut) internal returns (uint256 amountOut) {
        if (tokenIn != address(WETH)) {
            revert NonWethToken(WETH, tokenIn);
        }
        if (tokenOut != address(0)) {
            revert NonEthToken(tokenOut);
        }
        uint256 amountIn = IWETH(WETH).balanceOf(address(this));
        IWETH(WETH).withdraw(amountIn);
        amountOut = address(this).balance;
    }

    // Make a v2 version for this too
    // USDM-swap
    function _usdmSwap(address tokenIn, address tokenOut) internal returns (uint256 amountOut) {
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, tokenIn, tokenOut));
        uint256 amountIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 receivedAmount =
            IUSDM(tokenIn).convertToTokens(IUSDM(tokenIn).convertToShares(IERC20(tokenIn).balanceOf(address(this))));

        (uint256 poolIn, uint256 poolOut) = ButtonswapLibrary.getPools(factory, tokenIn, tokenOut);
        amountOut = ButtonswapLibrary.getAmountOut(receivedAmount, poolIn, poolOut);

        TransferHelper.safeApprove(tokenIn, address(pair), amountIn);
        if (tokenIn < tokenOut) {
            pair.swap(amountIn, 0, 0, amountOut, address(this));
        } else {
            pair.swap(0, amountIn, amountOut, 0, address(this));
        }
    }

    function _swapStep(address tokenIn, SwapStep calldata swapStep)
        internal
        virtual
        returns (address tokenOut, uint256 amountOut)
    {
        tokenOut = swapStep.tokenOut;
        if (swapStep.operation == ButtonswapOperations.Swap.SWAP) {
            amountOut = _swap(tokenIn, tokenOut, swapStep.data);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_BUTTON) {
            amountOut = _wrapButton(tokenIn, tokenOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_BUTTON) {
            amountOut = _unwrapButton(tokenIn, tokenOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_WETH) {
            amountOut = _wrapWETH(tokenIn, tokenOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_WETH) {
            amountOut = _unwrapWETH(tokenIn, tokenOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.USDM_SWAP) {
            amountOut = _usdmSwap(tokenIn, tokenOut);
        }
    }

    function _swapExactTokensForTokens(address tokenIn, uint256 amountIn, SwapStep[] calldata swapSteps)
        internal
        returns (uint256[] memory amounts, address tokenOut, uint256 amountOut)
    {
        tokenOut = tokenIn;
        amountOut = amountIn;
        amounts = new uint256[](swapSteps.length + 1);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < swapSteps.length; i++) {
            (tokenOut, amountOut) = _swapStep(tokenOut, swapSteps[i]);
            amounts[i + 1] = amountOut;
        }
    }

    function _transferTokensOut(address tokenOut, SwapStep[] calldata swapSteps, address to) internal {
        // If swapSteps is empty or the last swapStep isn't unwrap-weth, then transfer out the entire balance of tokenOut
        if (swapSteps.length == 0 || swapSteps[swapSteps.length - 1].operation != ButtonswapOperations.Swap.UNWRAP_WETH)
        {
            TransferHelper.safeTransfer(tokenOut, to, IERC20(tokenOut).balanceOf(address(this)));
        } else {
            // Otherwise, transfer out the entire balance
            payable(to).transfer(address(this).balance);
        }
    }

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

        // Doing the swaps one-by-one
        // Repurposing tokenIn/amountIn variables to represent finalTokenOut/finalAmountOut to save gas
        (amounts, tokenIn, amountIn) = _swapExactTokensForTokens(tokenIn, amountIn, swapSteps);

        // Confirm that the final amountOut is greater than or equal to the amountOutMin
        if (amountIn < amountOutMin) {
            revert InsufficientOutputAmount(amountOutMin, amountIn);
        }

        // Transferring output balance to to-address
        _transferTokensOut(tokenIn, swapSteps, to);
    }

    function _getAmountIn(address tokenIn, uint256 amountOut, SwapStep calldata swapStep)
        internal
        virtual
        returns (uint256 amountIn)
    {
        if (swapStep.operation == ButtonswapOperations.Swap.SWAP) {
            (uint8 version, uint16 plBps, uint16 feeBps) = ButtonswapV2Library.decodeData(swapStep.data);
            if (version == 1) {
                (uint256 poolIn, uint256 poolOut) = ButtonswapLibrary.getPools(factory, tokenIn, swapStep.tokenOut);
                amountIn = ButtonswapLibrary.getAmountIn(amountOut, poolIn, poolOut);
            } else if (version == 2) {
                (uint256 poolIn, uint256 poolOut) =
                    ButtonswapV2Library.getPools(v2Factory, tokenIn, swapStep.tokenOut, plBps, feeBps);
                amountIn = ButtonswapV2Library.getAmountIn(amountOut, poolIn, poolOut, plBps, feeBps);
            }
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_BUTTON) {
            amountIn = IButtonToken(swapStep.tokenOut).wrapperToUnderlying(amountOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_BUTTON) {
            amountIn = IButtonToken(tokenIn).underlyingToWrapper(amountOut);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_WETH) {
            amountIn = amountOut;
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_WETH) {
            amountIn = amountOut;
        } else if (swapStep.operation == ButtonswapOperations.Swap.USDM_SWAP) {
            (uint256 poolIn, uint256 poolOut) = ButtonswapLibrary.getPools(factory, tokenIn, swapStep.tokenOut);
            amountIn = ButtonswapLibrary.getAmountIn(amountOut, poolIn, poolOut) + 4;
        }
    }

    function _getAmountIn(address tokenIn, uint256 amountOut, SwapStep[] calldata swapSteps)
        internal
        returns (uint256 amountIn)
    {
        amountIn = amountOut;
        if (swapSteps.length > 0) {
            for (uint256 i = swapSteps.length - 1; i > 0; i--) {
                amountIn = _getAmountIn(swapSteps[i - 1].tokenOut, amountIn, swapSteps[i]);
            }
            // Do the last iteration outside of the loop since we need to use tokenIn
            amountIn = _getAmountIn(tokenIn, amountIn, swapSteps[0]);
        }
    }

    function _getAmountOut(address tokenIn, uint256 amountIn, SwapStep calldata swapStep)
        internal
        virtual
        returns (uint256 amountOut)
    {
        if (swapStep.operation == ButtonswapOperations.Swap.SWAP) {
            (uint8 version, uint16 plBps, uint16 feeBps) = ButtonswapV2Library.decodeData(swapStep.data);
            if (version == 1) {
                (uint256 poolIn, uint256 poolOut) = ButtonswapLibrary.getPools(factory, tokenIn, swapStep.tokenOut);
                amountOut = ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut);
            } else if (version == 2) {
                (uint256 poolIn, uint256 poolOut) =
                    ButtonswapV2Library.getPools(v2Factory, tokenIn, swapStep.tokenOut, plBps, feeBps);
                amountOut = ButtonswapV2Library.getAmountOut(amountIn, poolIn, poolOut, plBps, feeBps);
            }
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_BUTTON) {
            amountOut = IButtonToken(swapStep.tokenOut).underlyingToWrapper(amountIn);
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_BUTTON) {
            amountOut = IButtonToken(tokenIn).wrapperToUnderlying(amountIn);
        } else if (swapStep.operation == ButtonswapOperations.Swap.WRAP_WETH) {
            amountOut = amountIn;
        } else if (swapStep.operation == ButtonswapOperations.Swap.UNWRAP_WETH) {
            amountOut = amountIn;
        } else if (swapStep.operation == ButtonswapOperations.Swap.USDM_SWAP) {
            (uint256 poolIn, uint256 poolOut) = ButtonswapLibrary.getPools(factory, tokenIn, swapStep.tokenOut);
            amountOut = ButtonswapLibrary.getAmountOut(
                IUSDM(tokenIn).convertToTokens(IUSDM(tokenIn).convertToShares(amountIn)), poolIn, poolOut
            );
        }
    }

    function _getAmountOut(address tokenIn, uint256 amountIn, SwapStep[] calldata swapSteps)
        internal
        returns (uint256 amountOut)
    {
        amountOut = amountIn;
        if (swapSteps.length > 0) {
            // Do the first iteration outside of the loop since we need to use tokenIn
            amountOut = _getAmountOut(tokenIn, amountOut, swapSteps[0]);

            for (uint256 i = 1; i < swapSteps.length; i++) {
                amountOut = _getAmountOut(swapSteps[i - 1].tokenOut, amountOut, swapSteps[i]);
            }
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
        //        amounts = _getAmountsIn(tokenIn, amountOut, swapSteps);
        uint256 amountIn = _getAmountIn(tokenIn, amountOut, swapSteps);

        if (amountIn > amountInMax) {
            revert ExcessiveInputAmount(amountInMax, amountIn);
        }

        // Transferring in the initial amount if the first swapStep is not wrap-weth
        if (swapSteps[0].operation != ButtonswapOperations.Swap.WRAP_WETH) {
            TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        } else if (amountIn < amountInMax) {
            // Refund the surplus input ETH to the user if the first swapStep is wrap-weth
            payable(msg.sender).transfer(amountInMax - amountIn);
        }

        // Reusing tokenIn/amountIn as finalTokenIn/finalAmountIn
        (amounts, tokenIn, amountIn) = _swapExactTokensForTokens(tokenIn, amountIn, swapSteps);

        // Validate that sufficient output was returned
        if (amountIn < amountOut) {
            revert InsufficientOutputAmount(amountOut, amountIn);
        }

        // Transferring output balance to to-address
        _transferTokensOut(tokenIn, swapSteps, to);
    }

    function _transferSwapStepsIn(address pair, address tokenIn, uint256 amountIn, SwapStep[] calldata swapSteps)
        internal
        returns (uint256[] memory amounts, uint256 finalAmountIn)
    {
        // Transferring in tokenA from user if first swapStepsA is not wrap-weth
        if (swapSteps.length == 0 || swapSteps[0].operation != ButtonswapOperations.Swap.WRAP_WETH) {
            TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        }

        // Repurposing tokenIn/amountIn variables as finalTokenIn/finalAmountIn to save gas
        (amounts, tokenIn, amountIn) = _swapExactTokensForTokens(tokenIn, amountIn, swapSteps);

        // Approving final tokenA for transfer to pair
        TransferHelper.safeApprove(tokenIn, pair, amountIn);
        finalAmountIn = amountIn;
    }

    function _getPairVersion(bytes memory data) internal pure returns (uint8 version) {
        assembly {
            version := mload(add(data, 0x01))
        }
    }

    function _validateMovingAveragePrice0ThresholdV1(
        uint256 movingAveragePrice0,
        uint256 movingAveragePrice0ThresholdBps,
        uint256 pool0,
        uint256 pool1
    ) internal pure {
        uint256 cachedTerm = Math.mulDiv(movingAveragePrice0, pool0 * BPS, 2 ** 112);
        // Check above lowerbound
        if ((movingAveragePrice0ThresholdBps < BPS) && pool1 * (BPS - movingAveragePrice0ThresholdBps) > cachedTerm) {
            revert MovingAveragePriceOutOfBounds(pool0, pool1, movingAveragePrice0, movingAveragePrice0ThresholdBps);
        }
        // Check below upperbound
        if (pool1 * (BPS + movingAveragePrice0ThresholdBps) < cachedTerm) {
            revert MovingAveragePriceOutOfBounds(pool0, pool1, movingAveragePrice0, movingAveragePrice0ThresholdBps);
        }
    }

    function _validateMovingAveragePrice0ThresholdV2(
        uint256 movingAveragePrice0,
        uint256 movingAveragePrice0ThresholdBps,
        uint256 pool0,
        uint256 pool1,
        uint16 plBps
    ) internal pure {
        uint256 price0 = ButtonswapV2Library.price(pool1, pool0, plBps);
        // Check above lowerbound
        if (
            (movingAveragePrice0ThresholdBps < BPS)
                && (BPS * price0 < (BPS - movingAveragePrice0ThresholdBps) * movingAveragePrice0)
        ) {
            revert MovingAveragePriceOutOfBounds(pool0, pool1, movingAveragePrice0, movingAveragePrice0ThresholdBps);
        }
        // Check below upperbound
        uint256 cachedTerm = BPS + movingAveragePrice0ThresholdBps;
        if (movingAveragePrice0 < type(uint256).max / cachedTerm) {
            // Can check without mulDiv
            if (BPS * price0 > cachedTerm * movingAveragePrice0) {
                revert MovingAveragePriceOutOfBounds(pool0, pool1, movingAveragePrice0, movingAveragePrice0ThresholdBps);
            }
        } else {
            // Require mulDiv to check
            if (Math.mulDiv(BPS, price0, 2 ** 112) > Math.mulDiv(cachedTerm, movingAveragePrice0, 2 ** 112)) {
                revert MovingAveragePriceOutOfBounds(pool0, pool1, movingAveragePrice0, movingAveragePrice0ThresholdBps);
            }
        }
    }

    function _validateMovingAveragePrice0Threshold(
        uint256 movingAveragePrice0ThresholdBps,
        uint256 pool0,
        uint256 pool1,
        IButtonswapPair pair,
        bytes memory data
    ) internal view {
        uint8 version = _getPairVersion(data);
        // Validate that the moving average price is within the threshold for pairs that exist
        // Skip if pair doesn't exist yet (empty pools) or if movingAveragePrice0ThresholdBps is maximum
        if (pool0 > 0 && pool1 > 0 && movingAveragePrice0ThresholdBps < type(uint256).max) {
            uint256 movingAveragePrice0 = pair.movingAveragePrice0();
            if (version == 1) {
                _validateMovingAveragePrice0ThresholdV1(
                    movingAveragePrice0, movingAveragePrice0ThresholdBps, pool0, pool1
                );
            } else if (version == 2) {
                (, uint16 plBps,) = ButtonswapV2Library.decodeData(data);
                _validateMovingAveragePrice0ThresholdV2(
                    movingAveragePrice0, movingAveragePrice0ThresholdBps, pool0, pool1, plBps
                );
            }
        }
    }

    function _calculateDualSidedAddAmounts(
        AddLiquidityParams calldata addLiquidityParams,
        IButtonswapPair pair,
        bool aToken0
    ) internal returns (uint256 amountA, uint256 amountB) {
        // Fetch pair liquidity
        uint256 poolA;
        uint256 poolB;
        uint256 reservoirA;
        uint256 reservoirB;
        if (aToken0) {
            (poolA, poolB, reservoirA, reservoirB,) = pair.getLiquidityBalances();
        } else {
            (poolB, poolA, reservoirB, reservoirA,) = pair.getLiquidityBalances();
        }

        // If pair has no liquidity, then deposit addLiquidityParams.amountADesired and addLiquidityParams.amountBDesired
        if ((poolA + reservoirA) == 0 && (poolB + reservoirB) == 0) {
            (amountA, amountB) = (addLiquidityParams.amountADesired, addLiquidityParams.amountBDesired);
        } else {
            // Calculate optimal amountB and check if it fits
            uint256 amountOptimal = _getAmountIn(
                addLiquidityParams.tokenB,
                ButtonswapLibrary.quote(
                    _getAmountOut(
                        addLiquidityParams.tokenA, addLiquidityParams.amountADesired, addLiquidityParams.swapStepsA
                    ),
                    poolA + reservoirA,
                    poolB + reservoirB
                ),
                addLiquidityParams.swapStepsB
            );
            if (amountOptimal <= addLiquidityParams.amountBDesired) {
                if (amountOptimal < addLiquidityParams.amountBMin) {
                    revert InsufficientTokenAmount(
                        addLiquidityParams.tokenB, amountOptimal, addLiquidityParams.amountBMin
                    );
                }
                (amountA, amountB) = (addLiquidityParams.amountADesired, amountOptimal);
            } else {
                // Calculate optimal amountA (repurposing variable to save gas) and check if it fits
                amountOptimal = _getAmountIn(
                    addLiquidityParams.tokenA,
                    ButtonswapLibrary.quote(
                        _getAmountOut(
                            addLiquidityParams.tokenB, addLiquidityParams.amountBDesired, addLiquidityParams.swapStepsB
                        ),
                        poolB + reservoirB,
                        poolA + reservoirA
                    ),
                    addLiquidityParams.swapStepsA
                );
                assert(amountOptimal <= addLiquidityParams.amountADesired); // This case should never happen
                if (amountOptimal < addLiquidityParams.amountAMin) {
                    revert InsufficientTokenAmount(
                        addLiquidityParams.tokenA, amountOptimal, addLiquidityParams.amountAMin
                    );
                }
                (amountA, amountB) = (amountOptimal, addLiquidityParams.amountBDesired);
            }
        }

        // Validate that the moving average price is within the threshold for pairs that already existed
        _validateMovingAveragePrice0Threshold(
            addLiquidityParams.movingAveragePrice0ThresholdBps,
            aToken0 ? poolA : poolB,
            aToken0 ? poolB : poolA,
            pair,
            addLiquidityParams.data
        );
    }

    function _addLiquidityDual(
        IButtonswapPair pair,
        bool aToken0,
        AddLiquidityParams calldata addLiquidityParams,
        address to
    ) internal returns (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) {
        // Calculating how much of tokenA and tokenB to take from user
        (uint256 amountA, uint256 amountB) = _calculateDualSidedAddAmounts(addLiquidityParams, pair, aToken0);

        (amountsA, amountA) =
            _transferSwapStepsIn(address(pair), addLiquidityParams.tokenA, amountA, addLiquidityParams.swapStepsA);
        (amountsB, amountB) =
            _transferSwapStepsIn(address(pair), addLiquidityParams.tokenB, amountB, addLiquidityParams.swapStepsB);

        if (aToken0) {
            liquidity = pair.mint(amountA, amountB, to);
        } else {
            liquidity = pair.mint(amountB, amountA, to);
        }
    }

    // Works for both V1 and V2
    function _addLiquidityGetMintSwappedAmountsV2(
        AddLiquidityParams calldata addLiquidityParams,
        address pairTokenA,
        address pairTokenB,
        bool isReservoirA
    ) internal returns (uint256 amountA, uint256 amountB) {
        address pairAddress = _getPair(pairTokenA, pairTokenB, addLiquidityParams.data);

        // ReservoirA is non-empty
        if (isReservoirA) {
            // we take from reservoirA and the user-provided amountBDesired
            // But modify so that you don't do liquidityOut logic since you don't need it
            (, uint256 amountAOptimal) = ButtonswapV2Library.getMintSwappedAmounts(
                pairAddress,
                pairTokenB,
                pairTokenA,
                _getAmountOut(
                    addLiquidityParams.tokenB, addLiquidityParams.amountBDesired, addLiquidityParams.swapStepsB
                )
            );
            amountAOptimal = _getAmountIn(addLiquidityParams.tokenA, amountAOptimal, addLiquidityParams.swapStepsA);
            // Slippage-check: User wants to drain from the res by amountAMin or more
            if (amountAOptimal < addLiquidityParams.amountAMin) {
                revert InsufficientTokenAmount(addLiquidityParams.tokenA, amountAOptimal, addLiquidityParams.amountAMin);
            }
            (amountA, amountB) = (0, addLiquidityParams.amountBDesired);
        } else {
            // ReservoirB is non-empty
            // we take from reservoirB and the user-provided amountADesired
            (, uint256 amountBOptimal) = ButtonswapV2Library.getMintSwappedAmounts(
                pairAddress,
                pairTokenA,
                pairTokenB,
                _getAmountOut(
                    addLiquidityParams.tokenA, addLiquidityParams.amountADesired, addLiquidityParams.swapStepsA
                )
            );
            amountBOptimal = _getAmountIn(addLiquidityParams.tokenB, amountBOptimal, addLiquidityParams.swapStepsB);
            // Slippage-check: User wants to drain from the res by amountBMin or more
            if (amountBOptimal < addLiquidityParams.amountBMin) {
                revert InsufficientTokenAmount(addLiquidityParams.tokenB, amountBOptimal, addLiquidityParams.amountBMin);
            }
            (amountA, amountB) = (addLiquidityParams.amountADesired, 0);
        }
    }

    function _calculateSingleSidedAddAmounts(
        AddLiquidityParams calldata addLiquidityParams,
        IButtonswapPair pair,
        address pairTokenA,
        address pairTokenB
    ) internal returns (uint256 amountA, uint256 amountB) {
        // Fetch pair liquidity
        uint256 poolA;
        uint256 poolB;
        uint256 reservoirA;
        uint256 reservoirB;
        if (pairTokenA < pairTokenB) {
            (poolA, poolB, reservoirA, reservoirB,) = pair.getLiquidityBalances();
        } else {
            (poolB, poolA, reservoirB, reservoirA,) = pair.getLiquidityBalances();
        }

        // If poolA and poolB are both 0, then the pair hasn't been initialized yet
        if (poolA == 0 || poolB == 0) {
            revert NotInitialized(address(pair));
        }
        // If reservoirA and reservoirB are both 0, then the pair doesn't have a non-empty reservoir
        if (reservoirA == 0 && reservoirB == 0) {
            revert NoReservoir(address(pair));
        }

        //        (amountA, amountB) = _addLiquidityGetMintSwappedAmounts(addLiquidityParams, pairTokenA, pairTokenB, reservoirA > 0);
        (amountA, amountB) =
            _addLiquidityGetMintSwappedAmountsV2(addLiquidityParams, pairTokenA, pairTokenB, reservoirA > 0);
    }

    function _addLiquiditySingle(
        IButtonswapPair pair,
        address pairTokenA,
        address pairTokenB,
        AddLiquidityParams calldata addLiquidityParams,
        address to
    ) internal returns (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity) {
        // Calculating how much of tokenA and tokenB to take from user
        (uint256 amountA, uint256 amountB) =
            _calculateSingleSidedAddAmounts(addLiquidityParams, pair, pairTokenA, pairTokenB);

        if (amountA > 0) {
            (amountsA, amountA) =
                _transferSwapStepsIn(address(pair), addLiquidityParams.tokenA, amountA, addLiquidityParams.swapStepsA);
            liquidity = pair.mintWithReservoir(amountA, to);
        } else if (amountB > 0) {
            (amountsB, amountB) =
                _transferSwapStepsIn(address(pair), addLiquidityParams.tokenB, amountB, addLiquidityParams.swapStepsB);
            liquidity = pair.mintWithReservoir(amountB, to);
        }
    }

    function _getPair(address pairTokenA, address pairTokenB, bytes memory data)
        internal
        view
        returns (address pairAddress)
    {
        uint8 version = _getPairVersion(data);

        if (version == 1) {
            pairAddress = IButtonswapFactory(factory).getPair(pairTokenA, pairTokenB);
        } else if (version == 2) {
            (, uint16 plBps, uint16 feeBps) = ButtonswapV2Library.decodeData(data);
            pairAddress = IButtonswapV2Factory(v2Factory).getPair(pairTokenA, pairTokenB, plBps, feeBps);
        } else {
            revert UnsupportedVersion(version);
        }
    }

    function _createPair(address pairTokenA, address pairTokenB, bytes memory data)
        internal
        returns (address pairAddress)
    {
        uint8 version = _getPairVersion(data);

        if (version == 1) {
            pairAddress = IButtonswapFactory(factory).createPair(pairTokenA, pairTokenB);
        } else if (version == 2) {
            (, uint16 plBps, uint16 feeBps) = ButtonswapV2Library.decodeData(data);
            pairAddress = IButtonswapV2Factory(v2Factory).createPair(pairTokenA, pairTokenB, plBps, feeBps);
        } else {
            revert UnsupportedVersion(version);
        }
    }

    function _addLiquidityGetOrCreatePair(AddLiquidityParams calldata addLiquidityParams)
        internal
        returns (address pairAddress, address pairTokenA, address pairTokenB)
    {
        // No need to validate if finalTokenA or finalTokenB are address(0) since getPair and createPair will handle it
        pairTokenA = addLiquidityParams.swapStepsA.length > 0
            ? addLiquidityParams.swapStepsA[addLiquidityParams.swapStepsA.length - 1].tokenOut
            : addLiquidityParams.tokenA;
        pairTokenB = addLiquidityParams.swapStepsB.length > 0
            ? addLiquidityParams.swapStepsB[addLiquidityParams.swapStepsB.length - 1].tokenOut
            : addLiquidityParams.tokenB;

        // Fetch the pair
        pairAddress = _getPair(pairTokenA, pairTokenB, addLiquidityParams.data);

        // Pair doesn't exist
        if (pairAddress == address(0)) {
            // If the operation is dual-sided and createPair is true, then create the pair. Otherwise throw an error
            if (addLiquidityParams.operation == ButtonswapOperations.Liquidity.DUAL && addLiquidityParams.createPair) {
                pairAddress = _createPair(pairTokenA, pairTokenB, addLiquidityParams.data);
            } else {
                // ToDo: Update error to include v2 params: plBps, feeBps?
                revert PairDoesNotExist(pairTokenA, pairTokenB);
            }
        } else if (addLiquidityParams.createPair) {
            // ToDo: Update error to include v2 params: plBps, feeBps?
            // The pair already exists but createPair is true
            revert PairAlreadyExists(pairTokenA, pairTokenB, pairAddress);
        }
    }

    function addLiquidity(AddLiquidityParams calldata addLiquidityParams, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity)
    {
        (address pairAddress, address pairTokenA, address pairTokenB) = _addLiquidityGetOrCreatePair(addLiquidityParams);

        if (addLiquidityParams.operation == ButtonswapOperations.Liquidity.DUAL) {
            (amountsA, amountsB, liquidity) =
                _addLiquidityDual(IButtonswapPair(pairAddress), pairTokenA < pairTokenB, addLiquidityParams, to);
        } else if (addLiquidityParams.operation == ButtonswapOperations.Liquidity.SINGLE) {
            (amountsA, amountsB, liquidity) =
                _addLiquiditySingle(IButtonswapPair(pairAddress), pairTokenA, pairTokenB, addLiquidityParams, to);
        }

        if (liquidity < addLiquidityParams.liquidityMin) {
            revert InsufficientOutputLiquidity(liquidity, addLiquidityParams.liquidityMin);
        }
    }

    function _removeLiquidityDual(
        IButtonswapPair pair,
        RemoveLiquidityParams calldata removeLiquidityParams,
        address to
    ) internal returns (uint256[] memory amountsA, uint256[] memory amountsB) {
        // Burn the pair-tokens for amountA of tokenA and amountB of tokenB
        (address token0,) = ButtonswapLibrary.sortTokens(removeLiquidityParams.tokenA, removeLiquidityParams.tokenB);
        uint256 amountA;
        uint256 amountB;
        if (removeLiquidityParams.tokenA == token0) {
            (amountA, amountB) = pair.burn(removeLiquidityParams.liquidity, address(this));
        } else {
            (amountB, amountA) = pair.burn(removeLiquidityParams.liquidity, address(this));
        }

        // Repurposing amountA/amountB variables to represent finalOutputAmountA/finalOutputAmountB (after all the swaps) to save gas
        address finalTokenA;
        address finalTokenB;
        (amountsA, finalTokenA, amountA) =
            _swapExactTokensForTokens(removeLiquidityParams.tokenA, amountA, removeLiquidityParams.swapStepsA);
        (amountsB, finalTokenB, amountB) =
            _swapExactTokensForTokens(removeLiquidityParams.tokenB, amountB, removeLiquidityParams.swapStepsB);

        // Validate that enough of tokenA/B (after all the swaps) was received
        if (amountA < removeLiquidityParams.amountAMin) {
            revert InsufficientTokenAmount(finalTokenA, amountA, removeLiquidityParams.amountAMin);
        }
        if (amountB < removeLiquidityParams.amountBMin) {
            revert InsufficientTokenAmount(finalTokenB, amountB, removeLiquidityParams.amountBMin);
        }

        // Transfer finalTokenA/finalTokenB to the user
        _transferTokensOut(finalTokenA, removeLiquidityParams.swapStepsA, to);
        _transferTokensOut(finalTokenB, removeLiquidityParams.swapStepsB, to);
    }

    function _removeLiquiditySingle(
        IButtonswapPair pair,
        RemoveLiquidityParams calldata removeLiquidityParams,
        address to
    ) internal returns (uint256[] memory amountsA, uint256[] memory amountsB) {
        // Burn the pair-tokens for amountA of tokenA and amountB of tokenB
        (address token0,) = ButtonswapLibrary.sortTokens(removeLiquidityParams.tokenA, removeLiquidityParams.tokenB);
        uint256 amountA;
        uint256 amountB;
        if (removeLiquidityParams.tokenA == token0) {
            (amountA, amountB) = pair.burnFromReservoir(removeLiquidityParams.liquidity, address(this));
        } else {
            (amountB, amountA) = pair.burnFromReservoir(removeLiquidityParams.liquidity, address(this));
        }

        // Repurposing amountA/amountB variables to represent finalOutputAmountA/finalOutputAmountB (after all the swaps) to save gas
        address finalTokenA;
        address finalTokenB;
        if (amountA > 0) {
            (amountsA, finalTokenA, amountA) =
                _swapExactTokensForTokens(removeLiquidityParams.tokenA, amountA, removeLiquidityParams.swapStepsA);
            finalTokenB = removeLiquidityParams.tokenB;
        } else {
            (amountsB, finalTokenB, amountB) =
                _swapExactTokensForTokens(removeLiquidityParams.tokenB, amountB, removeLiquidityParams.swapStepsB);
            finalTokenA = removeLiquidityParams.tokenA;
        }

        // Validate that enough of tokenA/B (after all the swaps) was received
        if (amountA < removeLiquidityParams.amountAMin) {
            revert InsufficientTokenAmount(finalTokenA, amountA, removeLiquidityParams.amountAMin);
        }
        if (amountB < removeLiquidityParams.amountBMin) {
            revert InsufficientTokenAmount(finalTokenB, amountB, removeLiquidityParams.amountBMin);
        }

        // Transfer finalTokenA/finalTokenB to the user
        _transferTokensOut(finalTokenA, removeLiquidityParams.swapStepsA, to);
        _transferTokensOut(finalTokenB, removeLiquidityParams.swapStepsB, to);
    }

    function _removeLiquidity(IButtonswapPair pair, RemoveLiquidityParams calldata removeLiquidityParams, address to)
        internal
        returns (uint256[] memory amountsA, uint256[] memory amountsB)
    {
        // Transfer pair-tokens to the router from msg.sender
        pair.transferFrom(msg.sender, address(this), removeLiquidityParams.liquidity);

        // Route to the appropriate internal removeLiquidity function based on the operation
        if (removeLiquidityParams.operation == ButtonswapOperations.Liquidity.DUAL) {
            return _removeLiquidityDual(pair, removeLiquidityParams, to);
        } else if (removeLiquidityParams.operation == ButtonswapOperations.Liquidity.SINGLE) {
            return _removeLiquiditySingle(pair, removeLiquidityParams, to);
        }
    }

    function _removeLiquidityGetPair(RemoveLiquidityParams calldata removeLiquidityParams)
        internal
        view
        returns (address pairAddress)
    {
        pairAddress = _getPair(removeLiquidityParams.tokenA, removeLiquidityParams.tokenB, removeLiquidityParams.data);
        // If pair doesn't exist, throw error
        if (pairAddress == address(0)) {
            revert PairDoesNotExist(removeLiquidityParams.tokenA, removeLiquidityParams.tokenB);
        }
    }

    function removeLiquidity(RemoveLiquidityParams calldata removeLiquidityParams, address to, uint256 deadline)
        external
        ensure(deadline)
        returns (uint256[] memory amountsA, uint256[] memory amountsB)
    {
        // Fetch the pair
        IButtonswapPair pair = IButtonswapPair(_removeLiquidityGetPair(removeLiquidityParams));
        // Remove liquidity
        return _removeLiquidity(pair, removeLiquidityParams, to);
    }

    function removeLiquidityWithPermit(
        RemoveLiquidityParams calldata removeLiquidityParams,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external ensure(deadline) returns (uint256[] memory amountsA, uint256[] memory amountsB) {
        // Fetch the pair
        IButtonswapPair pair = IButtonswapPair(_removeLiquidityGetPair(removeLiquidityParams));
        // Call permit on the pair
        uint256 value = approveMax ? type(uint256).max : removeLiquidityParams.liquidity;
        pair.permit(msg.sender, address(this), value, deadline, v, r, s);
        // Remove liquidity
        return _removeLiquidity(pair, removeLiquidityParams, to);
    }
}
