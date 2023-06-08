// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IButtonswapFactory} from
"buttonswap-periphery_buttonswap-core/interfaces/IButtonswapFactory/IButtonswapFactory.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {IRootButtonswapRouter} from "./interfaces/IButtonswapRouter/IRootButtonswapRouter.sol";
import {ButtonswapLibrary} from "./libraries/ButtonswapLibrary.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {console} from "buttonswap-periphery_forge-std/Console.sol";

contract RootButtonswapRouter is IRootButtonswapRouter {
    /**
     * @inheritdoc IRootButtonswapRouter
     */
    address public immutable override factory;

    /**
     * @inheritdoc IRootButtonswapRouter
     */
    address public immutable override WETH;

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    /**
     * @dev Only accepts ETH via fallback from the WETH contract
     */
    receive() external payable {
        assert(msg.sender == WETH);
    }

    // ToDo: Update this to keep totalA:totalB ratio (NOT JUST poolA:poolB)
    // ToDo: Update unit tests to validate that poolA:poolB ratio isn't sufficient^^^
    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        address pair = IButtonswapFactory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            IButtonswapFactory(factory).createPair(tokenA, tokenB);
        }

        uint256 totalA = IERC20(tokenA).balanceOf(pair);
        uint256 totalB = IERC20(tokenB).balanceOf(pair);

        if (totalA == 0 && totalB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = ButtonswapLibrary.quote(amountADesired, totalA, totalB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) {
                    revert InsufficientBAmount();
                }
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = ButtonswapLibrary.quote(amountBDesired, totalB, totalA);
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) {
                    revert InsufficientAAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
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
            (,uint256 amountAOptimal) =
            ButtonswapLibrary.getMintSwappedAmounts(factory, tokenB, tokenA, amountBDesired);
            // User wants to drain to the res by amountAMin or more
            // Slippage-check
            if (amountAOptimal < amountAMin) {
                revert InsufficientAAmount();
            }
            (amountA, amountB) = (0, amountBDesired);
            console.log("amountA", amountA);
            console.log("amountB", amountB);
        } else {
            // we take from reservoirB and the user-provided amountADesired
            (, uint256 amountBOptimal) = ButtonswapLibrary.getMintSwappedAmounts(factory, tokenA, tokenB, amountADesired);
            if (amountBOptimal < amountBMin) {
                revert InsufficientBAmount();
            }
            (amountA, amountB) = (amountADesired, 0);
            console.log("amountA", amountA);
            console.log("amountB", amountB);
        }
    }

    // **** SWAP ****
    /**
     * @dev requires the initial amount to have already been sent to the first pair
     */
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

//    // Return the input token's pool, output token's pool, and input token's reservoir
//    function _getSortedPoolsAndReservoirs(IButtonswapPair pair, bool inputIsFirst)
//    internal
//    view
//    returns (uint256 poolInput, uint256 poolOutput, uint256 reservoirInput)
//    {
//        (uint256 pool0, uint256 pool1, uint256 reservoir0, uint256 reservoir1,) = pair.getLiquidityBalances();
//        return inputIsFirst ? (pool0, pool1, reservoir0) : (pool1, pool0, reservoir1);
//    }

    // ToDo: Put this back in after fixing all the other bugs. This requires IR :/
    //    // **** SWAP (supporting fee-on-transfer tokens) ****
    //    // requires the initial amount to have already been sent to the first pair
    //    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
    //        for (uint256 i; i < path.length - 1; i++) {
    //            (address input, address output) = (path[i], path[i + 1]);
    //            (address token0,) = ButtonswapLibrary.sortTokens(input, output);
    //            IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, input, output));
    //
    //            uint256 amountInput;
    //            uint256 amountOutput;
    //            {
    //                // scope to avoid stack too deep errors
    //                (uint256 poolInput, uint256 poolOutput, uint256 reservoirInput) =
    //                    _getSortedPoolsAndReservoirs(pair, input == token0);
    //
    //                amountInput = IERC20(input).balanceOf(address(pair)) - poolInput - reservoirInput;
    //                amountOutput = ButtonswapLibrary.getAmountOut(amountInput, poolInput, poolOutput);
    //            }
    //            (uint256 amount0In, uint256 amount1In) =
    //            input == token0 ? (amountInput, uint256(0)) : (uint256(0), amountInput);
    //
    //            (uint256 amount0Out, uint256 amount1Out) =
    //                input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
    //            address to = i < path.length - 2 ? ButtonswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
    //            pair.swap(amount0In, amount1In, amount0Out, amount1Out, to, new bytes(0));
    //        }
    //    }
}
