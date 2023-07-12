// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IButtonswapFactory} from
    "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapFactory/IButtonswapFactory.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {IRootButtonswapRouter} from "./interfaces/IButtonswapRouter/IRootButtonswapRouter.sol";
import {ButtonswapLibrary} from "./libraries/ButtonswapLibrary.sol";
import {Math} from "./libraries/Math.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract RootButtonswapRouter is IRootButtonswapRouter {
    uint256 private constant BPS = 10_000;

    /**
     * @inheritdoc IRootButtonswapRouter
     */
    address public immutable override factory;

    constructor(address _factory) {
        factory = _factory;
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint16 movingAveragePriceThresholdBps
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        address pair = IButtonswapFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = IButtonswapFactory(factory).createPair(tokenA, tokenB);
        }

        (uint256 poolA, uint256 poolB, uint256 reservoirA, uint256 reservoirB) =
            ButtonswapLibrary.getLiquidityBalances(factory, tokenA, tokenB);

        if ((poolA + reservoirA) == 0 && (poolB + reservoirB) == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = ButtonswapLibrary.quote(amountADesired, (poolA + reservoirA), (poolB + reservoirB));
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) {
                    revert InsufficientBAmount();
                }
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal =
                    ButtonswapLibrary.quote(amountBDesired, (poolB + reservoirB), (poolA + reservoirA));
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) {
                    revert InsufficientAAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }

        // Validate that the moving average price is within the threshold for pairs that exist
        if (poolA > 0 && poolB > 0) {
            uint256 movingAveragePrice = IButtonswapPair(pair).movingAveragePrice0();
            if (tokenA < tokenB) {
                // tokenA is token0
                if (
                    poolB * BPS
                        > Math.mulDiv(poolA * (BPS + movingAveragePriceThresholdBps), movingAveragePrice, 2 ** 112)
                        || Math.mulDiv(poolA * (BPS - movingAveragePriceThresholdBps), movingAveragePrice, 2 ** 112)
                            > poolB * BPS
                ) {
                    revert MovingAveragePriceOutOfBounds();
                }
            } else {
                // tokenB is token0
                if (
                    poolA * BPS
                        > Math.mulDiv(poolB * (BPS + movingAveragePriceThresholdBps), movingAveragePrice, 2 ** 112)
                        || Math.mulDiv(poolB * (BPS - movingAveragePriceThresholdBps), movingAveragePrice, 2 ** 112)
                            > poolA * BPS
                ) {
                    revert MovingAveragePriceOutOfBounds();
                }
            }
        }
    }

    function _addLiquidityWithReservoir(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // If the pair doesn't exist yet, there isn't any reservoir
        if (IButtonswapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            revert NoReservoir();
        }
        (uint256 poolA, uint256 poolB, uint256 reservoirA, uint256 reservoirB) =
            ButtonswapLibrary.getLiquidityBalances(factory, tokenA, tokenB);
        // the first liquidity addition should happen through _addLiquidity
        // can't initialize by matching with a reservoir
        if (poolA == 0 || poolB == 0) {
            revert NotInitialized();
        }
        if (reservoirA == 0 && reservoirB == 0) {
            revert NoReservoir();
        }

        if (reservoirA > 0) {
            // we take from reservoirA and the user-provided amountBDesired
            // But modify so that you don't do liquidityOut logic since you don't need it
            (, uint256 amountAOptimal) =
                ButtonswapLibrary.getMintSwappedAmounts(factory, tokenB, tokenA, amountBDesired);
            // User wants to drain to the res by amountAMin or more
            // Slippage-check
            if (amountAOptimal < amountAMin) {
                revert InsufficientAAmount();
            }
            (amountA, amountB) = (0, amountBDesired);
        } else {
            // we take from reservoirB and the user-provided amountADesired
            (, uint256 amountBOptimal) =
                ButtonswapLibrary.getMintSwappedAmounts(factory, tokenA, tokenB, amountADesired);
            if (amountBOptimal < amountBMin) {
                revert InsufficientBAmount();
            }
            (amountA, amountB) = (amountADesired, 0);
        }
    }

    // **** SWAP ****

    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = ButtonswapLibrary.sortTokens(input, output);
            uint256 amountIn = amounts[i];
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0In, uint256 amount1In) = input == token0 ? (amountIn, uint256(0)) : (uint256(0), amountIn);
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));

            address to = i < path.length - 2 ? address(this) : _to;
            IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, input, output));
            TransferHelper.safeApprove(input, address(pair), amountIn);
            pair.swap(amount0In, amount1In, amount0Out, amount1Out, to);
        }
    }
}
