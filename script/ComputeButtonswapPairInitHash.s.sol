// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "buttonswap-periphery_forge-std/Script.sol";
import {console} from "buttonswap-periphery_forge-std/console.sol";
import {ButtonswapPair} from "buttonswap-periphery_buttonswap-core/ButtonswapPair.sol";

contract ComputeButtonswapPairInitHash is Script {
    function run() external view {
        bytes32 initHashCode = keccak256(abi.encodePacked(type(ButtonswapPair).creationCode));
        console.log("The initHashCode is as follows:");
        console.logBytes32(initHashCode);
    }
}
