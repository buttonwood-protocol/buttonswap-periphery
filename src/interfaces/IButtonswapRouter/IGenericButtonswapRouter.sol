// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import {ButtonswapOperations} from "../../libraries/ButtonswapOperations.sol";
import {IGenericButtonswapRouterErrors} from "./IGenericButtonswapRouterErrors.sol";

interface IGenericButtonswapRouter is IGenericButtonswapRouterErrors {
    /**
     * @notice Struct for swapping tokens
     * @param operation The operation to perform: (SWAP, WRAP_BUTTON, UNWRAP_BUTTON, WRAP_WETH, UNWRAP_WETH)
     * @param tokenOut The address of the output token to swap to. If ETH (or network currency), address(0) is used.
     */
    struct SwapStep {
        ButtonswapOperations.Swap operation;
        address tokenOut;
    }

    /**
     * @notice Struct for adding liquidity
     * @dev The last `SwapStep.tokenOut` of `swapStepsA` and `swapStepsB` determine the pair to add liquidity to.
     * If they do not exist, then `tokenA` and `tokenB` are used.
     * @param operation Whether to perform dual- or single- sided liquidity provision
     * @param tokenA The address of the first token provided
     * @param tokenB The address of the second token provided
     * @param swapStepsA The swap steps to transform tokenA before adding liquidity
     * @param swapStepsB The swap steps to transform tokenB before adding liquidity
     * @param amountADesired The maximum amount of tokenA to provide
     * @param amountBDesired The maximum amount of tokenB to provide
     * @param amountAMin The minimum amount of the first token to provide
     * @param amountBMin The minimum amount of the second token to provide
     * @param movingAveragePrice0ThresholdBps The percentage threshold that movingAveragePrice0 can deviate from the current price.
     */
    struct AddLiquidityStep {
        ButtonswapOperations.Liquidity operation; // Potentially just separate out the function
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

    /**
     * @notice Struct for removing liquidity
     * @dev `tokenA` and `tokenB` determine the pair to remove liquidity from. The output the tokens the user receives
     * are determined by `swapStepsA` and `swapStepsB`. If they do not exist, then `tokenA` and `tokenB` are used.
     * @param operation Whether to perform dual- or single- sided liquidity withdrawal
     * @param tokenA The address of the first token in the pair
     * @param tokenB The address of the second token in the pair
     * @param swapStepsA The swap steps to transform tokenA after removing it from the pair
     * @param swapStepsB The swap steps to transform tokenB after removing it from the pair
     * @param liquidity The amount of liquidity tokens to burn
     * @param amountAMin The minimum amount of the first token to receive
     * @param amountBMin The minimum amount of the second token to receive
     */
    struct RemoveLiquidityStep {
        ButtonswapOperations.Liquidity operation;
        address tokenA;
        address tokenB;
        SwapStep[] swapStepsA;
        SwapStep[] swapStepsB;
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

    /**
     * @notice Given an ordered array of tokens, performs consecutive swaps/transformation operations from a specific amount of the first token to the last token in the swapSteps array.
     * @param tokenIn The address of the input token
     * @param amountIn The amount of the first token to swap
     * @param amountOutMin The minimum amount of the last token to receive from the swap
     * @param swapSteps An array of SwapStep structs representing the path the input token takes to get to the output token
     * @param to The address to send the output token to.
     * @param deadline The time after which this transaction can no longer be executed.
     */
    function swapExactTokensForTokens(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        SwapStep[] calldata swapSteps,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    // Example: exact ETH > WETH > stETH
    /**
     * swapExactTokensForTokens(
     *     address(0),
     *     5*10**18,
     *     4*10**18,
     *     [
     *         IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.WRAP_ETH, address(weth)),
     *         IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.SWAP, address(stETH))
     *     ],
     *     toAddress,
     *     deadline
     * );
     */

    /**
     * @notice Given an ordered array of tokens, performs consecutive swaps/transformation operations from the first token to a specific amount of the last token in the swapSteps array.
     * @dev Note: If there is excess balance stored in the contract, it will be transferred out. Thus the actual amount received may be more than the `amountOut` specified.
     * @param tokenIn The address of the input token
     * @param amountOut The amount of the last token to receive from the swap.
     * @param amountInMax The maximum amount of the first token to swap.
     * @param swapSteps An array of SwapStep structs representing the path the input token takes to get to the output token
     * @param to The address to send the output token to.
     * @param deadline The time after which this transaction can no longer be executed.
     */
    function swapTokensForExactTokens(
        address tokenIn,
        uint256 amountOut,
        uint256 amountInMax,
        SwapStep[] calldata swapSteps,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
    // Example: stETH > rrETH > rETH
    /**
     * swapTokensForExactTokens(
     *     address(stETH)
     *     4*10**18,
     *     5*10**18,
     *     [
     *         IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.SWAP, address(rebasingRocketEth))
     *         IGenericButtonswapRouter.SwapStep(ButtonswapOperations.Swap.UNWRAP_BUTTON, address(rocketETH)),
     *     ],
     *     toAddress,
     *     deadline
     * );
     */

    /**
     * @notice Adds liquidity to a pair and transfers the liquidity tokens to the recipient.
     * @dev If `addLiquidityStep.liquidity` is `ButtonswapOperations.Liquidity.DUAL`, then first the pair is created if it doesn't exist yet.
     * If the pair is empty, `addLiquidityStep.amountAMin` and `addLiquidityStep.amountBMin` are ignored.
     * If the pair is nonempty, it deposits as much of `addLiquidityStep.tokenA` and `addLiquidityStep.tokenB` as possible
     * (after applying `addLiquidityStep.swapStepsA` and `addLiquidityStep.swapStepsB`) while maintaining 3 conditions:
     * 1. The ratio of final tokenA to final tokenB in the pair remains approximately the same
     * 2. The amount of `addLiquidityStep.tokenA` provided from the sender is at least `addLiquidityStep.amountAMin` but less than or equal to `addLiquidityStep.amountADesired`
     * 3. The amount of `addLiquidityStep.tokenB` provided from the sender is at least `addLiquidityStep.amountBMin` but less than or equal to `addLiquidityStep.amountBDesired`
     * @dev If `addLiquidityStep.liquidity` is `ButtonswapOperations.Liquidity.SINGLE`, it only adds liquidity opposite to the pair's existing reservoir.this
     * Since there at most one reservoir at a given time, some conditions are checked:
     * 1. If there is no reservoir, it rejects
     * 2. The token corresponding to the existing reservoir has its corresponding amountDesired parameter ignored
     * 3. The reservoir is deducted from and transformed into the corresponding output token (after applying swapSteps), and then checked against corresponding amountMin parameter.
     * @param addLiquidityStep The AddLiquidityStep struct containing all the parameters necessary to add liquidity
     * @param to The address to send the liquidity tokens to.
     * @param deadline The time after which this transaction can no longer be executed.
     */
    function addLiquidity(AddLiquidityStep calldata addLiquidityStep, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amountsA, uint256[] memory amountsB, uint256 liquidity);
    // Example: (ETH -> WETH) + (rETH -> rrETH)
    /**
     * addLiquidity(
     *     IGenericButtonswapRouter.AddLiquidityStep(
     *         ButtonswapOperations.Liquidity.DUAL,
     *         address(0),
     *         address(rETH),
     *         [
     *             IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.WRAP_WETH, address(weth))
     *         ],
     *         [
     *             IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.WRAP_BUTTON, address(rrETH))
     *         ],
     *         4000 * 10**18,
     *         4000 * 10**18,
     *         3000 * 10**18,
     *         3000 * 10**18,
     *         1,
     *     ),
     *     toAddress,
     *     deadline
     * );
     */

    /**
     * @notice Removes liquidity from a pair, and transfers the tokens to the recipient.
     * @dev `removeLiquidityStep.liquidity` determines whether to perform dual- or single- sided liquidity withdrawal.
     * @param removeLiquidityStep The RemoveLiquidityStep struct containing all the parameters necessary to remove liquidity
     * @param to The address to send the tokens to.
     * @param deadline The time after which this transaction can no longer be executed.
     */
    function removeLiquidity(RemoveLiquidityStep calldata removeLiquidityStep, address to, uint256 deadline)
        external
        returns (uint256[] memory amountsA, uint256[] memory amountsB);
    // Example: (WETH -> ETH) - (rrETH -> stETH)
    /**
     * removeLiquidity(
     *     IGenericButtonswapRouter.RemoveLiquidityStep(
     *         ButtonswapOperations.Liquidity.DUAL,
     *         address(WETH),
     *         address(rrETH),
     *         [
     *             IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.UNWRAP_WETH, address(0))
     *         ],
     *         [
     *             IGenericButtonswapRouter.SwapStep(ButtonSwapOperation.Swap.SWAP, address(stETH))
     *         ],
     *         2000 * 10**18,
     *         2000 * 10**18,
     *         2000 * 10**18,
     *         1,
     *     ),
     *     toAddress,
     *     deadline
     * );
     */

    /**
     * @notice Similar to `removeLiquidity()` but utilizes the Permit signatures to reduce gas consumption.
     * Removes liquidity from a pair, and transfers the tokens to the recipient.
     * @param removeLiquidityStep The RemoveLiquidityStep struct containing all the parameters necessary to remove liquidity
     * @param to The address to send the tokens to.
     * @param deadline The time after which this transaction can no longer be executed.
     * @param approveMax Whether the signature is for the max uint256 or liquidity value
     * @param v Part of the signature
     * @param r Part of the signature
     * @param s Part of the signature
     */
    function removeLiquidityWithPermit(
        RemoveLiquidityStep calldata removeLiquidityStep,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256[] memory amountsA, uint256[] memory amountsB);
}
