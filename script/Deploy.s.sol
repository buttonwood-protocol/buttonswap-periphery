// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript} from "./Base.s.sol";
import {ButtonswapRouter} from "../src/ButtonswapRouter.sol";

contract Deploy is BaseScript {
    function run() public virtual broadcast returns (ButtonswapRouter buttonswapRouter) {
        address _factory = 0x0000000000000000000000000000000000000000;
        address _WETH = 0x0000000000000000000000000000000000000000;
        buttonswapRouter = new ButtonswapRouter(_factory, _WETH);
    }
}
