pragma solidity ^0.8.13;

import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";

import "../interfaces/IERC20.sol";
import {IButtonswapRouter} from "../interfaces/IButtonswapRouter/IButtonswapRouter.sol";
import {ButtonswapLibrary} from "../libraries/ButtonswapLibrary.sol";
import {Babylonian} from "../libraries/Babylonian.sol";
import {TransferHelper} from "../libraries/TransferHelper.sol";

contract ExampleSwapToPrice {
    IButtonswapRouter public immutable router;
    address public immutable factory;

    constructor(address factory_, IButtonswapRouter router_) {
        factory = factory_;
        router = router_;
    }

    // computes the direction and magnitude of the profit-maximizing trade
    function computeProfitMaximizingTrade(
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 reserveA,
        uint256 reserveB
    ) public pure returns (bool aToB, uint256 amountIn) {
        aToB = (reserveA * truePriceTokenB) / reserveB < truePriceTokenA;

        uint256 invariant = reserveA * reserveB;

        uint256 leftSide = Babylonian.sqrt(
            (invariant * (aToB ? truePriceTokenA : truePriceTokenB) * 1000)
                / (uint256(aToB ? truePriceTokenB : truePriceTokenA) * 997)
        );
        uint256 rightSide = (aToB ? (reserveA * 1000) : (reserveB * 1000)) / 997;

        // compute the amount that must be sent to move the price to the profit-maximizing price
        amountIn = leftSide - rightSide;
    }

    // swaps an amount of either token such that the trade is profit-maximizing, given an external true price
    // true price is expressed in the ratio of token A to token B
    // caller must approve this contract to spend whichever token is intended to be swapped
    function swapToPrice(
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 maxSpendTokenA,
        uint256 maxSpendTokenB,
        address to,
        uint256 deadline
    ) public {
        // true price is expressed as a ratio, so both values must be non-zero
        require(truePriceTokenA != 0 && truePriceTokenB != 0, "ExampleSwapToPrice: ZERO_PRICE");
        // caller can specify 0 for either if they wish to swap in only one direction, but not both
        require(maxSpendTokenA != 0 || maxSpendTokenB != 0, "ExampleSwapToPrice: ZERO_SPEND");

        bool aToB;
        uint256 amountIn;
        {
            (uint256 poolA, uint256 poolB) = ButtonswapLibrary.getPools(factory, tokenA, tokenB);
            (aToB, amountIn) = computeProfitMaximizingTrade(truePriceTokenA, truePriceTokenB, poolA, poolB);
        }

        // spend up to the allowance of the token in
        uint256 maxSpend = aToB ? maxSpendTokenA : maxSpendTokenB;
        if (amountIn > maxSpend) {
            amountIn = maxSpend;
        }

        address tokenIn = aToB ? tokenA : tokenB;
        address tokenOut = aToB ? tokenB : tokenA;
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        TransferHelper.safeApprove(tokenIn, address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        router.swapExactTokensForTokens(
            amountIn,
            0, // amountOutMin: we can skip computing this number because the math is tested
            path,
            to,
            deadline
        );
    }
}
