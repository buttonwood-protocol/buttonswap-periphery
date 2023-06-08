// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapRouterErrors} from "../src/interfaces/IButtonswapRouter/IButtonswapRouterErrors.sol";
import {RootButtonswapRouter} from "../src/RootButtonswapRouter.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {MockWeth} from "./mocks/MockWeth.sol";

contract RootButtonswapRouterTest is Test, IButtonswapRouterErrors {
    address public userA;
    uint256 public userAPrivateKey;
    IWETH public weth;
    ButtonswapFactory public buttonswapFactory;
    RootButtonswapRouter public rootButtonswapRouter;

    function setUp() public {
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        weth = new MockWeth();
        buttonswapFactory = new ButtonswapFactory(userA);
        rootButtonswapRouter = new RootButtonswapRouter(address(buttonswapFactory), address(weth));
    }

    function test_WETH() public {
        assertEq(rootButtonswapRouter.WETH(), address(weth));
    }

    function test_factory() public {
        assertEq(rootButtonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_constructor() public {
        assertEq(rootButtonswapRouter.WETH(), address(weth));
        assertEq(rootButtonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_receive_rejectNonWETHSender(uint256 ethAmount) public {
        // Sending ETH, ignoring data in return value
        (bool sent,) = payable(address(rootButtonswapRouter)).call{value: ethAmount}("");
        assertTrue(!sent, "Expected call to fail");
    }

    function test_receive_acceptWETHSender(uint256 ethAmount) public {
        vm.deal(address(weth), ethAmount);
        vm.prank(address(weth));
        // Sending ETH, ignoring data in return value
        (bool sent,) = payable(address(rootButtonswapRouter)).call{value: ethAmount}("");
        assertTrue(sent, "Expected call to succeed");
    }
}
