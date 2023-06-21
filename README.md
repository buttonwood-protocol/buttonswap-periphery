# buttonswap-periphery

## `initHashCode`

The `initHashCode` value in the `pairFor` function in `ButtonswapLibrary.sol` is computed based on the `ButtonswapPair` contract from the `buttonswap-core` dependency.
As such this value must be updated whenever the dependency changes.

To do so, run `forge script ./scripts/ComputeInitHash.s.sol` and use the value it gives for `initHashCode` (after removing the `0x` prefix).
