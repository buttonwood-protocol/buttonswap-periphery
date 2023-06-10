// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapRouterErrors} from "../src/interfaces/IButtonswapRouter/IButtonswapRouterErrors.sol";
import {RootButtonswapRouter} from "../src/RootButtonswapRouter.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";

contract RootButtonswapRouterTest is Test, IButtonswapRouterErrors {
    address public userA;
    uint256 public userAPrivateKey;
    ButtonswapFactory public buttonswapFactory;
    RootButtonswapRouter public rootButtonswapRouter;

    function setUp() public {
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        buttonswapFactory = new ButtonswapFactory(userA);
        rootButtonswapRouter = new RootButtonswapRouter(address(buttonswapFactory));
    }

    function test_factory() public {
        assertEq(rootButtonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_constructor() public {
        assertEq(rootButtonswapRouter.factory(), address(buttonswapFactory));
    }
}
