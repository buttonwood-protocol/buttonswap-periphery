// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IButtonwoodRouterErrors} from "../src/interfaces/IButtonwoodRouter/IButtonwoodRouterErrors.sol";
import {ButtonwoodRouter} from "../src/ButtonwoodRouter.sol";
import {MockERC20} from "mock-contracts/MockERC20.sol";
import {ButtonswapFactory} from "buttonswap-core/ButtonswapFactory.sol";

contract ButtonwoodRouterTest is Test, IButtonwoodRouterErrors {
    address public userA = 0x000000000000000000000000000000000000000A;
    //    address public userB = 0x000000000000000000000000000000000000000b;
    //    address public userC = 0x000000000000000000000000000000000000000C;
    //    address public userD = 0x000000000000000000000000000000000000000d;

    MockERC20 public tokenA;
    MockERC20 public tokenB;
    address public wethAddress = 0x000000000000000000000000000000000000000E;
    ButtonswapFactory public buttonswapFactory;

    ButtonwoodRouter public buttonwoodRouter;

    function setUp() public {
        tokenA = new MockERC20("TokenA", "TKNA");
        tokenB = new MockERC20("TokenB", "TKNB");
        buttonswapFactory = new ButtonswapFactory(userA);
        buttonwoodRouter = new ButtonwoodRouter(address(buttonswapFactory), wethAddress);
    }

    function test_WETH() public {
        assertEq(buttonwoodRouter.WETH(), wethAddress);
    }

    function test_factory() public {
        assertEq(buttonwoodRouter.factory(), address(buttonswapFactory));
    }
}
