// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {DeployGenericButtonswapRouter} from "../script/DeployGenericButtonswapRouter.s.sol";
import {GenericButtonswapRouter} from "../src/GenericButtonswapRouter.sol";
import {Test} from "buttonswap-periphery_forge-std/Test.sol";

contract DeployGenericButtonswapRouterTest is Test {
    DeployGenericButtonswapRouter public deploy;

    function setUp() public {
        deploy = new DeployGenericButtonswapRouter();
    }

    function test_setup() public {
        GenericButtonswapRouter genericButtonswapRouter = deploy.run();
        assertNotEq(address(genericButtonswapRouter), address(0), "Validating GenericButtonswapRouter deploys with no errors");
    }
}
