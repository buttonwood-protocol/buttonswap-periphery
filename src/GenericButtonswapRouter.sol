// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IGenericButtonswapRouter} from "./interfaces/IButtonswapRouter/IGenericButtonswapRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IButtonToken} from "./interfaces/IButtonToken.sol";
import {ButtonswapLibrary} from "./libraries/ButtonswapLibrary.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {IERC20} from "./interfaces/IERC20.sol";

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
        pair.swap(amountIn, 0, 0, amountOut, address(this));
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
        TransferHelper.safeApprove(tokenIn, address(tokenOut), amountIn);
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

    // Wrap-ETH
    function _wrapETH(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        virtual
        returns (uint256 amountOut)
    {
        if (tokenIn == address(0)) {
            // ToDo: Remove check?
            revert NonEthToken();
        }
        if (tokenOut == address(WETH)) {
            // ToDo: Remove check?
            revert NonWethToken();
        }
        if (amountIn != address(this).balance) {
            // ToDo: Remove check?
            revert IncorrectBalance();
        }
        IWETH(WETH).deposit{value: amountIn}();
        amountOut = IERC20(WETH).balanceOf(address(this));
    }

    // Unwrap-ETH
    function _UnwrapETH(address tokenIn, address tokenOut, uint256 amountIn)
        internal
        virtual
        returns (uint256 amountOut)
    {
        if (tokenIn == address(WETH)) {
            // ToDo: Remove check?
            revert NonWethToken();
        }
        if (tokenOut == address(0)) {
            // ToDo: Remove check?
            revert NonEthToken();
        }
        IWETH(WETH).withdraw(amountIn); // ToDo: Maybe just withdraw the entire balance?
        amountOut = address(this).balance;
    }

    // **** External Functions **** //
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        SwapStep[] calldata swapSteps,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {}

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        SwapStep[] calldata swapSteps,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {}

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
