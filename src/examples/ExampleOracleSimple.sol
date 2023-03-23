pragma solidity ^0.8.13;

import { IButtonswapPair } from "buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import { UQ112x112 } from 'buttonswap-core/libraries/UQ112x112.sol';

import "../libraries/ButtonwoodOracleLibrary.sol";
import { ButtonwoodLibrary } from "../libraries/ButtonwoodLibrary.sol";

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract ExampleOracleSimple {
    using UQ112x112 for uint224;

    uint256 public constant PERIOD = 24 hours;

    IButtonswapPair immutable pair;
    address public immutable token0;
    address public immutable token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;
    uint224 public price0Average;
    uint224 public price1Average;

    constructor(address factory, address tokenA, address tokenB) public {
        IButtonswapPair _pair = IButtonswapPair(ButtonwoodLibrary.pairFor(factory, tokenA, tokenB));
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getPools();
        require(reserve0 != 0 && reserve1 != 0, "ExampleOracleSimple: NO_RESERVES"); // ensure that there's liquidity in the pair
    }

    function update() external {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            ButtonwoodOracleLibrary.currentCumulativePrices(address(pair));
        // overflow is desired
        uint32 timeElapsed;
        unchecked {
            timeElapsed = blockTimestamp - blockTimestampLast;
        }

        // ensure that at least one full period has passed since the last update
        require(timeElapsed >= PERIOD, "ExampleOracleSimple: PERIOD_NOT_ELAPSED");

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        unchecked {
            price0Average = uint224((price0Cumulative - price0CumulativeLast) / timeElapsed);
            price1Average = uint224((price1Cumulative - price1CumulativeLast) / timeElapsed);
        }

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut) {
        if (token == token0) {
            amountOut = (price0Average * amountIn) >> 112;
        } else {
            require(token == token1, "ExampleOracleSimple: INVALID_TOKEN");
            amountOut = (price1Average * amountIn) >> 112;
        }
    }
}
