// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IETHButtonswapRouter} from "./IETHButtonswapRouter.sol";

interface IButtonswapRouter is IETHButtonswapRouter {
    /**
     * @notice Given some amount of an asset and pair pools, returns an equivalent amount of the other asset
     * @param amountA The amount of token A
     * @param poolA The balance of token A in the pool
     * @param poolB The balance of token B in the pool
     * @return amountB The amount of token B
     */
    function quote(uint256 amountA, uint256 poolA, uint256 poolB) external pure returns (uint256 amountB);

    /**
     * @notice Given an input amount of an asset and pair pools, returns the maximum output amount of the other asset
     * Factors in the fee on the input amount.
     * @param amountIn The input amount of the asset
     * @param poolIn The balance of the input asset in the pool
     * @param poolOut The balance of the output asset in the pool
     * @return amountOut The output amount of the other asset
     */
    function getAmountOut(uint256 amountIn, uint256 poolIn, uint256 poolOut)
        external
        pure
        returns (uint256 amountOut);

    /**
     * @notice Given an output amount of an asset and pair pools, returns a required input amount of the other asset
     * @param amountOut The output amount of the asset
     * @param poolIn The balance of the input asset in the pool
     * @param poolOut The balance of the output asset in the pool
     * @return amountIn The required input amount of the other asset
     */
    function getAmountIn(uint256 amountOut, uint256 poolIn, uint256 poolOut) external pure returns (uint256 amountIn);

    /**
     * @notice Given an ordered array of tokens and an input amount of the first asset, performs chained getAmountOut calculations to calculate the output amount of the final asset
     * @param amountIn The input amount of the first asset
     * @param path An array of token addresses [tokenA, tokenB, tokenC, ...] representing the path the input token takes to get to the output token
     * @return amounts The output amounts of each asset in the path
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    /**
     * @notice Given an ordered array of tokens and an output amount of the final asset, performs chained getAmountIn calculations to calculate the input amount of the first asset
     * @param amountOut The output amount of the final asset
     * @param path An array of token addresses [tokenA, tokenB, tokenC, ...] representing the path the input token takes to get to the output token
     * @return amounts The input amounts of each asset in the path
     */
    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    //ToDo: Put back in later
    //    function removeLiquidityETHSupportingFeeOnTransferTokens(
    //        address token,
    //        uint256 liquidity,
    //        uint256 amountTokenMin,
    //        uint256 amountETHMin,
    //        address to,
    //        uint256 deadline
    //    ) external returns (uint256 amountETH);
    //
    //    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
    //        address token,
    //        uint256 liquidity,
    //        uint256 amountTokenMin,
    //        uint256 amountETHMin,
    //        address to,
    //        uint256 deadline,
    //        bool approveMax,
    //        uint8 v,
    //        bytes32 r,
    //        bytes32 s
    //    ) external returns (uint256 amountETH);

    //ToDo: Put back in later
    //    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    //        uint256 amountIn,
    //        uint256 amountOutMin,
    //        address[] calldata path,
    //        address to,
    //        uint256 deadline
    //    ) external;
    //
    //    function swapExactETHForTokensSupportingFeeOnTransferTokens(
    //        uint256 amountOutMin,
    //        address[] calldata path,
    //        address to,
    //        uint256 deadline
    //    ) external payable;
    //
    //    function swapExactTokensForETHSupportingFeeOnTransferTokens(
    //        uint256 amountIn,
    //        uint256 amountOutMin,
    //        address[] calldata path,
    //        address to,
    //        uint256 deadline
    //    ) external;
}
