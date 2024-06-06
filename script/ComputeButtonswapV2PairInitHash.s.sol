// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "buttonswap-periphery_forge-std/Script.sol";
import {console} from "buttonswap-periphery_forge-std/console.sol";
import {ButtonswapV2Pair} from "buttonswap-periphery_buttonswap-v2-core/ButtonswapV2Pair.sol";

contract ComputeButtonswapV2PairInitHash is Script {
    function run() external view {
        bytes32 initHashCode = keccak256(abi.encodePacked(type(ButtonswapV2Pair).creationCode));
        console.log("The initHashCode is as follows:");
        console.logBytes32(initHashCode);
    }
}
