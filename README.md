# buttonswap-periphery

## `initHashCode`

The `initHashCode` value in the `pairFor` function in `ButtonswapLibrary.sol` is computed based on the `ButtonswapPair` contract from the `buttonswap-core` dependency.
As such this value must be updated whenever the dependency changes.

To do so, run `forge script ./script/ComputeInitHash.s.sol` and use the value it gives for `initHashCode` (after removing the `0x` prefix).

## Deploying

First edit the `Deploy.s.sol` script to configure the constructor arguments as required. Then use the script as follows:
```
forge script script/Deploy.s.sol --broadcast --rpc-url sepolia --verify --watch
```

This will attempt to verify the contract at the same time, but if you get `Error: contract does not exist` error then verification can be done as follows:

First compute the constructor args in ABI encoded format:
```
cast abi-encode "constructor(address _factory, address _WETH)" 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000
```

Then substitute the appropriate values in the following:
```
forge verify-contract <deployed contract address> src/ButtonswapRouter.sol:ButtonswapRouter --chain sepolia --constructor-args <output from cast command> --watch
```
