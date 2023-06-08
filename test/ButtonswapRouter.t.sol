// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapRouterErrors} from "../src/interfaces/IButtonswapRouter/IButtonswapRouterErrors.sol";
import {ButtonswapRouter} from "../src/ButtonswapRouter.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IButtonswapPairErrors} from
    "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPairErrors.sol";
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {MockWeth} from "./mocks/MockWeth.sol";
import {ButtonswapLibrary} from "../src/libraries/ButtonswapLibrary.sol";

contract ButtonswapRouterTest is Test, IButtonswapRouterErrors {
    address public userA;
    uint256 public userAPrivateKey;
    IWETH public weth;
    ButtonswapFactory public buttonswapFactory;
    ButtonswapRouter public buttonswapRouter;

    // Utility function for creating and initializing pairs with poolA:poolB price ratio. Does not use ButtonwoodRouter
    function createAndInitializePair(MockRebasingERC20 tokenA1, MockRebasingERC20 tokenB1, uint256 poolA, uint256 poolB)
        private
        returns (IButtonswapPair pair, uint256 liquidityOut)
    {
        pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA1), address(tokenB1)));
        tokenA1.mint(address(this), poolA);
        tokenA1.approve(address(pair), poolA);
        tokenB1.mint(address(this), poolB);
        tokenB1.approve(address(pair), poolB);

        if (pair.token0() == address(tokenA1)) {
            liquidityOut = pair.mint(poolA, poolB, address(this));
        } else {
            liquidityOut = pair.mint(poolB, poolA, address(this));
        }
    }

    function setUp() public {
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        weth = new MockWeth();
        buttonswapFactory = new ButtonswapFactory(userA);
        buttonswapRouter = new ButtonswapRouter(address(buttonswapFactory), address(weth));
    }

    function test_quote(uint256 amountA, uint256 poolA, uint256 poolB) public {
        try buttonswapRouter.quote(amountA, poolA, poolB) returns (uint256 amountB) {
            assertEq(
                amountB, ButtonswapLibrary.quote(amountA, poolA, poolB), "Call succeeds but output is not as expected"
            );
        } catch (bytes memory reason) {
            // Fails with the same error as the library call
            vm.expectRevert(reason);
            ButtonswapLibrary.quote(amountA, poolA, poolB);
        }
    }

    function test_getAmountOut(uint256 amountIn, uint256 poolIn, uint256 poolOut) public {
        try buttonswapRouter.getAmountOut(amountIn, poolIn, poolOut) returns (uint256 amountOut) {
            assertEq(
                amountOut,
                ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut),
                "Call succeeds but output is not as expected"
            );
        } catch (bytes memory reason) {
            // Fails with the same error as the library call
            vm.expectRevert(reason);
            ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut);
        }
    }

    function test_getAmountIn(uint256 amountOut, uint256 poolIn, uint256 poolOut) public {
        try buttonswapRouter.getAmountIn(amountOut, poolIn, poolOut) returns (uint256 amountIn) {
            assertEq(
                amountIn,
                ButtonswapLibrary.getAmountIn(amountOut, poolIn, poolOut),
                "Call succeeds but output is not as expected"
            );
        } catch (bytes memory reason) {
            // Fails with the same error as the library call
            vm.expectRevert(reason);
            ButtonswapLibrary.getAmountIn(amountOut, poolIn, poolOut);
        }
    }

    function test_getAmountsOut(uint256 amountIn, address[] memory path) public {
        try buttonswapRouter.getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            assertEq(
                amounts,
                ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path),
                "Call succeeds but output is not as expected"
            );
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                // Skip these cases as they are not caught by vm.expectRevert
                // Tested in: `testFail_getAmountsOut`
            } else {
                // Fails with the same error as the library call
                vm.expectRevert(reason);
                ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
            }
        }
    }

    // Using a testFail to capture EvmErrors that are not caught by vm.expectRevert
    function testFail_getAmountsOut(uint256 amountIn, address[] memory path) public view {
        try buttonswapRouter.getAmountsOut(amountIn, path) {
            revert("Skip valid calls");
        } catch {
            // If the call fails, the library call should also fail
            ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
        }
    }

    function test_getAmountsIn(uint256 amountOut, address[] calldata path) public {
        try buttonswapRouter.getAmountsIn(amountOut, path) returns (uint256[] memory amounts) {
            assertEq(
                amounts,
                ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path),
                "Call succeeds but output is not as expected"
            );
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                // Skip these cases as they are not caught by vm.expectRevert
                // Tested in: `testFail_getAmountsIn`
            } else {
                // Fails with the same error as the library call
                vm.expectRevert(reason);
                ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);
            }
        }
    }

    // Using a testFail to capture EvmErrors that are not caught by vm.expectRevert
    function testFail_getAmountsIn(uint256 amountOut, address[] calldata path) public view {
        try buttonswapRouter.getAmountsIn(amountOut, path) {
            revert("Skip valid calls");
        } catch {
            // If the call fails, the library call should also fail
            ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);
        }
    }
}
