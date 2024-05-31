// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

import {Deploy} from "../script/Deploy.s.sol";
import {ButtonswapRouter} from "../src/ButtonswapRouter.sol";
import {Test} from "buttonswap-periphery_forge-std/Test.sol";

contract DeployTest is Test {
    Deploy public deploy;

    function setUp() public {
        deploy = new Deploy();
    }

    function test_setup() public {
        ButtonswapRouter buttonswapRouter = deploy.run();
        assertNotEq(address(buttonswapRouter), address(0), "Validating ButtonswapRouter deploys with no errors");
    }
}
