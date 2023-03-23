pragma solidity >=0.5.0; // ToDo - update to 0.8.13

import {IButtonswapPair } from 'buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol';
import { UQ112x112 } from 'buttonswap-core/libraries/UQ112x112.sol';


// library with helper methods for oracles that are concerned with computing average prices
library ButtonwoodOracleLibrary {
    using UQ112x112 for uint224;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(address pair)
        internal
        view
        returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp)
    {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = IButtonswapPair(pair).price0CumulativeLast();
        price1Cumulative = IButtonswapPair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IButtonswapPair(pair).getPools();
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed;
            unchecked {
                timeElapsed = blockTimestamp - blockTimestampLast;
            }
            // addition overflow is desired
            unchecked {
                // counterfactual
                price0Cumulative += uint256(UQ112x112.encode(reserve1).uqdiv(reserve0)) * timeElapsed;
                // counterfactual
                price1Cumulative += uint256(UQ112x112.encode(reserve0).uqdiv(reserve1)) * timeElapsed;
            }
        }
    }
}
