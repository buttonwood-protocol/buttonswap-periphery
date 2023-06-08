// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IButtonswapRouter} from "./interfaces/IButtonswapRouter/IButtonswapRouter.sol";
import {IButtonswapFactory} from
    "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapFactory/IButtonswapFactory.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {ButtonswapLibrary} from "./libraries/ButtonswapLibrary.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {ETHButtonswapRouter} from "./ETHButtonswapRouter.sol";

contract ButtonswapRouter is ETHButtonswapRouter, IButtonswapRouter {
    constructor(address _factory, address _WETH) ETHButtonswapRouter(_factory, _WETH) {}

    // **** LIBRARY FUNCTIONS ****

    /**
     * @inheritdoc IButtonswapRouter
     */
    function quote(uint256 amountA, uint256 poolA, uint256 poolB)
        public
        pure
        virtual
        override
        returns (uint256 amountB)
    {
        return ButtonswapLibrary.quote(amountA, poolA, poolB);
    }

    /**
     * @inheritdoc IButtonswapRouter
     */
    function getAmountOut(uint256 amountIn, uint256 poolIn, uint256 poolOut)
        public
        pure
        virtual
        override
        returns (uint256 amountOut)
    {
        return ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut);
    }

    /**
     * @inheritdoc IButtonswapRouter
     */
    function getAmountIn(uint256 amountOut, uint256 poolIn, uint256 poolOut)
        public
        pure
        virtual
        override
        returns (uint256 amountIn)
    {
        return ButtonswapLibrary.getAmountIn(amountOut, poolIn, poolOut);
    }

    /**
     * @inheritdoc IButtonswapRouter
     */
    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return ButtonswapLibrary.getAmountsOut(factory, amountIn, path);
    }

    /**
     * @inheritdoc IButtonswapRouter
     */
    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return ButtonswapLibrary.getAmountsIn(factory, amountOut, path);
    }

    /**
     * @inheritdoc IButtonswapRouter
     */
    function getMintSwappedAmounts(address tokenA, address tokenB, uint256 mintAmountA)
        public
        view
        virtual
        override
        returns (uint256 tokenAToSwap, uint256 swappedReservoirAmountB)
    {
        return ButtonswapLibrary.getMintSwappedAmounts(factory, tokenA, tokenB, mintAmountA);
    }

    /**
     * @inheritdoc IButtonswapRouter
     */
    function getBurnSwappedAmounts(address tokenA, address tokenB, uint256 liquidity)
        public
        view
        virtual
        override
        returns (uint256 tokenOutA, uint256 swappedReservoirAmountA)
    {
        return ButtonswapLibrary.getBurnSwappedAmounts(factory, tokenA, tokenB, liquidity);
    }
}
