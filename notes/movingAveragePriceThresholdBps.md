# MovingAveragePriceThresholdBps

This parameter is pass in to `addLiquidity` and `addLiquidityEth` to guarantee that the pair's current movingAveragePrice does not deviate too far from the current pool price.

The movingAveragePrice is represented in the pair as `movingAveragePrice0`, which is defined as the amount of token1 equivalent to `2**112` token0.

## Math
To ensure that the movingAveragePrice is within the threshold, we use the following math:
```math
\frac{pool0}{pool1} \cdot \frac{BPS - movingAveragePriceThresholdBps}{BPS} \leq \frac{2^{112}}{movingAveragePrice0} 
\\
\frac{2^{112}}{movingAveragePrice0} \leq \frac{pool0}{pool1} \cdot \frac{BPS + movingAveragePriceThresholdBps}{BPS}
```
These inequalities can be simplified to:
```math
```math
(pool0)(BPS - movingAveragePriceThresholdBps)(movingAveragePrice0) \leq (2^{112})(pool1)(BPS) 
\\
(2^{112})(pool1)(BPS) \leq (pool0)(BPS + movingAveragePriceThresholdBps)(movingAveragePrice0)
```
Given that the multiplications of $2^{112}$ just compares $(pool1)(BPS)$ by the upper bits (skip the bottom 112) of the other side of the inequalities, we can use mulDivs without any loss of precision. Bit-shifting doesn't work because of the phantom overflow beforehand. We thus simplify it as such:
```solidity
Math.mulDiv(pool0 * (BPS - movingAveragePriceThresholdBps), movingAveragePrice0, 2**112) <= (pool1)(BPS)

(pool1)(BPS) <= Math.mulDiv(pool0 * (BPS + movingAveragePriceThresholdBps), movingAveragePrice0, 2**112)
```
In the code, before, we simply check which token is token0 and then use the appropriate values of `poolA` and `poolB` in-place of `pool0` and `pool1`.
In addition, we invert the conditions to check for the reverting case.

## Code
The check exists inside of `RootButtonswapRouter.sol`:
```solidity
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
```
