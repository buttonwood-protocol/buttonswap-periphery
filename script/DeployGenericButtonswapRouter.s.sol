// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./Base.s.sol";
import {GenericButtonswapRouter} from "../src/GenericButtonswapRouter.sol";

contract DeployGenericButtonswapRouter is BaseScript {
    function run() public virtual broadcast returns (GenericButtonswapRouter genericButtonswapRouter) {
        address _factory = 0x0000000000000000000000000000000000000000;
        address _factoryV2 = 0x0000000000000000000000000000000000000000;
        address _WETH = 0x0000000000000000000000000000000000000000;
        genericButtonswapRouter = new GenericButtonswapRouter(_factory, _factoryV2, _WETH);
    }
}
