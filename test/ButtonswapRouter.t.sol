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
    address public feeToSetter;
    uint256 public feeToSetterPrivateKey;
    address public isCreationRestrictedSetter;
    uint256 public isCreationRestrictedSetterPrivateKey;
    address public isPausedSetter;
    uint256 public isPausedSetterPrivateKey;
    address public paramSetter;
    uint256 public paramSetterPrivateKey;
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
        (feeToSetter, feeToSetterPrivateKey) = makeAddrAndKey("feeToSetter");
        (isCreationRestrictedSetter, isCreationRestrictedSetterPrivateKey) =
            makeAddrAndKey("isCreationRestrictedSetter");
        (isPausedSetter, isPausedSetterPrivateKey) = makeAddrAndKey("isPausedSetter");
        (paramSetter, paramSetterPrivateKey) = makeAddrAndKey("paramSetter");
        weth = new MockWeth();
        buttonswapFactory = new ButtonswapFactory(
            feeToSetter, isCreationRestrictedSetter, isPausedSetter, paramSetter, "LP Token", "LP"
        );
        buttonswapRouter = new ButtonswapRouter(address(buttonswapFactory), address(weth));
    }

    function test_constructor() public {
        assertEq(buttonswapRouter.WETH(), address(weth));
        assertEq(buttonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_getPair_pairDoesNotExist(address tokenA, address tokenB) public {
        address pairAddress = buttonswapRouter.getPair(tokenA, tokenB);
        assertEq(pairAddress, address(0), "Pair should not exist");
    }

    function test_getPair_pairDoesNotExist(bytes32 saltA, bytes32 saltB, uint256 poolA, uint256 poolB) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18, 1e36);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18, 1e36);

        address expectedPairAddress = buttonswapFactory.createPair(address(tokenA), address(tokenB));
        address pairAddress = buttonswapRouter.getPair(address(tokenA), address(tokenB));

        assertEq(pairAddress, expectedPairAddress, "Pair addresses should be equal");
    }

    function test_isCreationRestricted(bool isCreationRestricted) public {
        vm.prank(isCreationRestrictedSetter);
        buttonswapFactory.setIsCreationRestricted(isCreationRestricted);

        bool factoryIsCreationRestricted = buttonswapFactory.isCreationRestricted();

        assertEq(buttonswapRouter.isCreationRestricted(), isCreationRestricted, "isCreationRestricted should be equal");
        assertEq(
            buttonswapRouter.isCreationRestricted(), factoryIsCreationRestricted, "isCreationRestricted should be equal"
        );
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

    function test_getAmountsOut_invalidPath(uint256 amountIn, address[] memory path) public {
        try buttonswapRouter.getAmountsOut(amountIn, path) {
            assert(false); // Should never hit this line
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

    function test_getAmountsOut_validPath(uint256 amountIn, uint256[] calldata seedPoolOutAmounts) public {
        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountIn = bound(amountIn, 1000, 10000);

        // Setting path length to be between 2 and 10
        vm.assume(seedPoolOutAmounts.length >= 2);
        uint256 pathLength = bound(seedPoolOutAmounts.length, 2, 11);
        uint256[] memory poolOutAmounts = new uint256[](pathLength);
        for (uint256 idx = 0; idx < pathLength; idx++) {
            poolOutAmounts[idx] = seedPoolOutAmounts[idx];
        }

        // Assuming the poolIn=10000, calculating poolOut amounts to avoid math overflow/underflow
        for (uint256 idx = 1; idx < poolOutAmounts.length; idx++) {
            // The pair-conversion rate will be bounded [0.9 , 10]
            poolOutAmounts[idx] = bound(poolOutAmounts[idx], 9000, 100000);
        }

        // Creating all the tokens for the path
        address[] memory path = new address[](poolOutAmounts.length);
        for (uint256 idx; idx < path.length; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18, 1e36);
            path[idx] = address(token);
        }

        // Create the pairs and populating the pools
        for (uint256 idx; idx < path.length - 1; idx++) {
            createAndInitializePair(
                MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx + 1]), 10000, poolOutAmounts[idx + 1]
            );
        }

        uint256[] memory expectedAmounts = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);

        uint256[] memory amounts = buttonswapRouter.getAmountsOut(amountIn, path);

        // Checking that the amounts in the trade are as expected
        assertEq(amounts, expectedAmounts, "Amounts in the trade are not as expected");
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
        try buttonswapRouter.getAmountsIn(amountOut, path) {
            assert(false); // Should never hit this line
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

    function test_getAmountsIn_validPath(uint256 amountOut, uint256[] calldata seedPoolOutAmounts) public {
        // Ensuring that amountOut is bounded to avoid errors/overflows/underflows
        amountOut = bound(amountOut, 900, 1000); // 1000 * (1.1^10) < minimum pool out amount

        // Setting path length to be between 2 and 10
        vm.assume(seedPoolOutAmounts.length >= 2);
        uint256 pathLength = bound(seedPoolOutAmounts.length, 2, 10);
        uint256[] memory poolOutAmounts = new uint256[](pathLength);
        for (uint256 idx = 0; idx < pathLength; idx++) {
            poolOutAmounts[idx] = seedPoolOutAmounts[idx];
        }

        // Assuming the poolIn=10000, calculating poolOut amounts to avoid math overflow/underflow
        for (uint256 idx = 1; idx < poolOutAmounts.length; idx++) {
            // The pair-conversion rate will be bounded [0.9 , 10]
            poolOutAmounts[idx] = bound(poolOutAmounts[idx], 9000, 100000);
        }

        // Creating all the tokens for the path
        address[] memory path = new address[](poolOutAmounts.length);
        for (uint256 idx; idx < path.length; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18, 1e36);
            path[idx] = address(token);
        }

        // Create the pairs and calculate expected amounts
        for (uint256 idx = path.length - 1; idx > 0; idx--) {
            createAndInitializePair(
                MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx - 1]), poolOutAmounts[idx], 10000
            );
        }

        uint256[] memory expectedAmounts = ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);

        uint256[] memory amounts = buttonswapRouter.getAmountsIn(amountOut, path);

        // Checking that the amounts in the trade are as expected
        assertEq(amounts, expectedAmounts, "Amounts in the trade are not as expected");
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

    function test_getMintSwappedAmounts(
        bytes32 saltA,
        bytes32 saltB,
        uint256 poolA,
        uint256 poolB,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint256 amountInA
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        amountInA = bound(amountInA, 0, type(uint112).max);

        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18, 1e36);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18, 1e36);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Ensuring that a A-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying the rebase
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        (uint256 expectedTokenAToSwap, uint256 expectedSwappedReservoirAmountB) = ButtonswapLibrary
            .getMintSwappedAmounts(address(buttonswapFactory), address(tokenA), address(tokenB), amountInA);

        (uint256 tokenAToSwap, uint256 swappedReservoirAmountB) =
            buttonswapRouter.getMintSwappedAmounts(address(tokenA), address(tokenB), amountInA);

        assertEq(tokenAToSwap, expectedTokenAToSwap, "tokenAToSwap should equal expectedTokenAToSwap");

        assertEq(
            swappedReservoirAmountB,
            expectedSwappedReservoirAmountB,
            "swappedReservoirAmountB should equal expectedSwappedReservoirAmountB"
        );
    }

    function test_getBurnSwappedAmounts(
        bytes32 saltA,
        bytes32 saltB,
        uint256 poolA,
        uint256 poolB,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint256 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18, 1e36);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18, 1e36);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Ensuring that a A-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying the rebase
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        uint256 totalSupply = pair.totalSupply();
        liquidity = bound(liquidity, 0, totalSupply);

        (uint256 expectedTokenOutA, uint256 expectedSwappedReservoirAmountA) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(tokenA), address(tokenB), liquidity
        );

        (uint256 tokenOutA, uint256 swappedReservoirAmountA) =
            buttonswapRouter.getBurnSwappedAmounts(address(tokenA), address(tokenB), liquidity);

        assertEq(tokenOutA, expectedTokenOutA, "tokenOutA should equal expectedTokenOutA");

        assertEq(
            swappedReservoirAmountA,
            expectedSwappedReservoirAmountA,
            "swappedReservoirAmountA should equal expectedSwappedReservoirAmountA"
        );
    }
}
