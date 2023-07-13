# MovingAveragePriceThresholdBps

This parameter is passed into `addLiquidity` and `addLiquidityEth` to guarantee that the pair's current movingAveragePrice does not deviate too far from the current pool price. It thus must be within a threshold bound around the current pool price.

On an abstract level, the check is:
```math
currentPrice \cdot (1 - movingAverageThreshold) \leq movingAveragePrice \leq currentPrice \cdot (1 + movingAverageThreshold)
```

The movingAveragePrice is represented in the pair as `movingAveragePrice0`, which is defined as the amount of token1 equivalent to `2**112` token0.

The movingAverageThreshold is a percentage that is represented by `movingAveragePrice0ThresholdBps` in basis points. In practice, it is divided by `BPS = 10_000`.

## Math
To ensure that the movingAveragePrice is within the threshold, we have the following conditions:
```math
{movingAveragePrice0 \over 2^{112}} \geq {pool1 \over pool0} \cdot (1 - {movingAveragePrice0ThresholdBps \over BPS})
```
```math
{movingAveragePrice0 \over 2^{112}} \leq {pool1 \over pool0} \cdot (1 + {movingAveragePrice0ThresholdBps \over BPS})
```
These can be rearranged as follows:
```math
movingAveragePrice0 \cdot pool0 \geq 2^{112} \cdot pool1 \cdot {BPS - movingAveragePrice0ThresholdBps \over BPS}
```
```math
movingAveragePrice0 \cdot pool0 \leq 2^{112} \cdot pool1 \cdot {BPS + movingAveragePrice0ThresholdBps \over BPS}
```
And finally:
```math
movingAveragePrice0 \cdot pool0 \cdot BPS \geq 2^{112} \cdot pool1 \cdot (BPS - movingAveragePrice0ThresholdBps)
```
```math
movingAveragePrice0 \cdot pool0 \cdot BPS \leq 2^{112} \cdot pool1 \cdot (BPS + movingAveragePrice0ThresholdBps)
```

## Code
Due to max integer constraints, it's actually simpler to divide by $2^{112}$ (which still requires a mulDiv to avoid phantom overflow).
This premature division has negligible impact the result.
```solidity
Math.mulDiv(movingAveragePrice0, pool0 * BPS, 2**112) >= pool1 * (BPS - movingAveragePrice0ThresholdBps)
```
```solidity
Math.mulDiv(movingAveragePrice0, pool0 * BPS, 2**112) <= pool1 * (BPS + movingAveragePrice0ThresholdBps)
```
In the code we simply check beforehand which token is token0 and then use the appropriate values of `poolA` and `poolB` in-place of `pool0` and `pool1`.
In addition we invert the conditions to check for the reverting case.

The check exists inside of `RootButtonswapRouter.sol`:
```solidity
// Validate that the moving average price is within the threshold for pairs that exist
if (poolA > 0 && poolB > 0) {
    uint256 movingAveragePrice0 = IButtonswapPair(pair).movingAveragePrice0();
    if (tokenA < tokenB) {
        // tokenA is token0
        uint256 cachedTerm = Math.mulDiv(movingAveragePrice0, poolA * BPS, 2 ** 112);
        if (
            poolB * (BPS - movingAveragePrice0ThresholdBps) > cachedTerm
                || poolB * (BPS + movingAveragePrice0ThresholdBps) < cachedTerm
        ) {
            revert MovingAveragePriceOutOfBounds();
        }
    } else {
        // tokenB is token0
        uint256 cachedTerm = Math.mulDiv(movingAveragePrice0, poolB * BPS, 2 ** 112);
        if (
            poolA * (BPS - movingAveragePrice0ThresholdBps) > cachedTerm
                || poolA * (BPS + movingAveragePrice0ThresholdBps) < cachedTerm
        ) {
            revert MovingAveragePriceOutOfBounds();
        }
    }
}
```