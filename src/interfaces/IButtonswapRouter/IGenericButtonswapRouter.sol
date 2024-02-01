// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import {ButtonswapOperations} from "../../libraries/ButtonswapOperations.sol";
import {IGenericButtonswapRouterErrors} from "./IGenericButtonswapRouterErrors.sol";

interface IGenericButtonswapRouter is IGenericButtonswapRouterErrors {
    struct SwapStep {
        ButtonswapOperations.Swap operation;
        address tokenOut;
    }

    // ToDo: Fold back into function signature (unless needs IR)
//    struct AddLiquidityStep {
//        ButtonswapOperations.AddLiquidity operation;
//        address tokenA;
//        address tokenB;
//        uint256 amountADesired;
//        uint256 amountBDesired;
//        uint256 amountAMin;
//        uint256 amountBMin;
//        uint16 movingAveragePrice0ThresholdBps;
//    }
    struct AddLiquidityStep {
        ButtonswapOperations.AddLiquidity operation; // Potentially just separate out the function
        address tokenA;
        address tokenB;
        SwapStep[] swapStepsA;
        SwapStep[] swapStepsB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        uint16 movingAveragePrice0ThresholdBps;
    }

    // ToDo: Fold back into function signature (unless need IR)
    struct RemoveLiquidityStep {
        ButtonswapOperations.RemoveLiquidity operation;
        address tokenA;
        address tokenB;
        uint256 liquidity;
        uint256 amountAMin;
        uint256 amountBMin;
    }

    /**
     * @notice Returns the address of the Buttonswap Factory
     * @return factory The address of the Buttonswap Factory
     */
    function factory() external view returns (address factory);
    /**
     * @notice Returns the address of the WETH token
     * @return WETH The address of the WETH token
     */
    function WETH() external view returns (address WETH);

    // Swap
    function swapExactTokensForTokens(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        SwapStep[] calldata swapSteps,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    // Example: exact ETH > stETH
    /**
     * swapExactTokensForTokens(
     *     5*10**18,
     *     5*10**18,
     *     [
     *         IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.WRAP_ETH, address(0), address(weth)),
     *         IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.SWAP, address(weth), address(stETH))
     *     ],
     *     toAddress,
     *     deadline
     * );
     */

    function swapTokensForExactTokens(
        address tokenIn,
        uint256 amountOut,
        uint256 amountInMax,
        SwapStep[] calldata swapSteps,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    // Example: stETH > exact rocketETH
    /**
     * swapTokensForExactTokens(
     *     5*10**18,
     *     5*10**18,
     *     [
     *         IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.SWAP, address(steth), address(buttonRocketEth))
     *         IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.UNWRAP_BUTTON, address(buttonRocketEth), address(rocketETH)),
     *     ],
     *     toAddress,
     *     deadline
     * );
     */

    // AddLiquidity
    function addLiquidity(
        AddLiquidityStep calldata addLiquidityStep,
//        SwapStep[] calldata swapStepsA,
//        SwapStep[] calldata swapStepsB,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity);
    // Example: bWETH + buttonRocketEth
    /**
     * addLiquidity(
     *     IGenericButtonswapRouter.AddLiquidityStep(
     *         ButtonswapOperations.AddLiquidity.ADD_LIQUIDITY,
     *         address(weth),
     *         address(buttonRocketEth),
     *         4000 * 10**18,
     *         2 * 10**18,
     *         3800 * 10**18,
     *         1 * 10**18,
     *     ),
     *     [
     *         IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.WRAP_WETH, address(0), address(weth))
     *         IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.WRAP_BUTTON, address(weth), address(buttonWeth)),
     *     ],
     *     [
     *         IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.WRAP_BUTTON, address(rocketETH), address(buttonRocketEth))
     *     ],
     *     toAddress,
     *     deadline
     * );
     */

    // RemoveLiquidity
    function removeLiquidity(
        RemoveLiquidityStep calldata removeLiquidityStep,
        SwapStep[] calldata swapStepsA,
        SwapStep[] calldata swapStepsB,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}
