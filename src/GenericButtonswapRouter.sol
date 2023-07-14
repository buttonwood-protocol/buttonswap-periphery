// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IGenericButtonswapRouter} from "./interfaces/IButtonswapRouter/IGenericButtonswapRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IButtonToken} from "./interfaces/IButtonToken.sol";
import {ButtonswapLibrary} from "./libraries/ButtonswapLibrary.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {ButtonswapOperations} from "./libraries/ButtonswapOperations.sol";

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
            revert Expired();
        }
        _;
    }

    /**
     * @dev Only accepts ETH via fallback from the WETH contract
     */
    receive() external payable {
        if (msg.sender != WETH) {
            revert NonWETHSender();
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
            revert IncorrectButtonUnderlying();
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
            revert IncorrectButtonUnderlying();
        }
        if (IERC20(tokenIn).balanceOf(address(this)) != amountIn) {
            // ToDo: Remove check?
            revert IncorrectBalance();
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
            // ToDo: Remove check?
            revert NonEthToken();
        }
        if (tokenOut != address(WETH)) {
            // ToDo: Remove check?
            revert NonWethToken();
        }
        if (amountIn != address(this).balance) {
            // ToDo: Remove check? Maybe just deposit the entire balance of the router so it's always empty.
            revert IncorrectBalance();
        }
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
            // ToDo: Remove check?
            revert NonWethToken();
        }
        if (tokenOut != address(0)) {
            // ToDo: Remove check?
            revert NonEthToken();
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

        amounts = new uint256[](swapSteps.length + 1);
        amounts[0] = amountIn;

        for (uint256 i = 0; i < swapSteps.length; i++) {
            (tokenIn, amountIn) = _swapStep(tokenIn, amountIn, swapSteps[i]);
            amounts[i + 1] = amountIn;
        }

        // The final value of amountIn is the last amountOut from the last _swapStep execution
        if (amountIn < amountOutMin) {
            revert InsufficientOutputAmount();
        }

        // Transferring out final amount if the last swapStep is not unwrap-weth
        // The final value of amountIn is the last amountOut from the last _swapStep execution
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
    function _getAmountsIn(address firstTokenIn, uint256 amountOut, SwapStep[] calldata swapSteps)
        internal
        virtual
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](swapSteps.length + 1);
        amounts[swapSteps.length] = amountOut;
        for (uint256 i = swapSteps.length; i > 0; i--) {
            if (i == 1) {
                amountOut = _getAmountIn(firstTokenIn, amountOut, swapSteps[i - 1]);
                amounts[i - 1] = amountOut;
            } else {
                amountOut = _getAmountIn(swapSteps[i - 2].tokenOut, amountOut, swapSteps[i - 1]);
                amounts[i - 1] = amountOut;
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
        amounts = _getAmountsIn(tokenIn, amountOut, swapSteps);
        if (amounts[0] > amountInMax) {
            revert ExcessiveInputAmount();
        }

        for (uint256 i = 0; i < swapSteps.length; i++) {
            (tokenIn, amountOut) = _swapStep(tokenIn, amounts[i], swapSteps[i]);
            if (amountOut != amounts[i + 1]) {
                revert InsufficientOutputAmount();
            }
        }

        // The final value of tokenIn is the last tokenOut from the swapSteps
        TransferHelper.safeTransfer(tokenIn, to, amountOut);
    }

    function addLiquidity(
        AddLiquidityStep calldata addLiquidityStep,
        SwapStep[] calldata swapStepsA,
        SwapStep[] calldata swapStepsB,
        uint16 movingAveragePrice0ThresholdBps,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {}

    function removeLiquidity(
        RemoveLiquidityStep calldata removeLiquidityStep,
        SwapStep[] calldata swapStepsA,
        SwapStep[] calldata swapStepsB,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {}
}
