// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {ButtonwoodLibrary} from "../../src/libraries/ButtonwoodLibrary.sol";
import {ButtonswapFactory} from "buttonswap-core/ButtonswapFactory.sol";
import {ButtonswapPair} from "buttonswap-core/ButtonswapPair.sol";
import {MockERC20} from "mock-contracts/MockERC20.sol";
import {MockRebasingERC20} from "mock-contracts/MockRebasingERC20.sol";

contract ButtonwoodLibraryTest is Test {
    address public userA = 0x000000000000000000000000000000000000000A;

    ButtonswapFactory public buttonswapFactory;

    function setUp() public {
        buttonswapFactory = new ButtonswapFactory(address(this));
    }

    function test_sortTokens_validAddresses(address tokenA, address tokenB) public {
        // Ensuring that the addresses are not equal
        vm.assume(tokenA != tokenB);
        // Ensuring that the addresses are not zero
        vm.assume(tokenA != address(0));
        vm.assume(tokenB != address(0));

        // Figure out which address is first and which is second
        address firstToken = tokenA;
        address secondToken = tokenB;
        if (tokenA > tokenB) {
            firstToken = tokenB;
            secondToken = tokenA;
        }

        // Call the sortTokens function
        (address token0, address token1) = ButtonwoodLibrary.sortTokens(tokenA, tokenB);

        // Assert that the addresses are sorted correctly
        assertEq(token0, firstToken);
        assertEq(token1, secondToken);
    }

    function test_sortTokens_cannotCallWithIdenticalAddresses(address token) public {
        // Ensuring the IdenticalAddresses error is thrown
        vm.expectRevert(ButtonwoodLibrary.IdenticalAddresses.selector);
        ButtonwoodLibrary.sortTokens(token, token);
    }

    function test_sortTokens_cannotCallWithZeroAddress(address token, bool firstTokenIsZero) public {
        // Making sure not to trigger the IdenticalAddresses error
        vm.assume(token != address(0));

        address tokenA = address(0);
        address tokenB = token;
        if (!firstTokenIsZero) {
            tokenA = token;
            tokenB = address(0);
        }

        // Ensuring the ZeroAddress error is thrown
        vm.expectRevert(ButtonwoodLibrary.ZeroAddress.selector);
        ButtonwoodLibrary.sortTokens(tokenA, tokenB);
    }

    function test_pairFor(address tokenA, address tokenB) public {
        // Ensuring that the addresses are not equal
        vm.assume(tokenA != tokenB);
        // Ensuring that the addresses are not zero
        vm.assume(tokenA != address(0));
        vm.assume(tokenB != address(0));

        // Create the pair with the factory and two tokens
        address factoryPair = buttonswapFactory.createPair(tokenA, tokenB);

        // Call the pairFor function to get the pair address
        address pair = ButtonwoodLibrary.pairFor(address(buttonswapFactory), tokenA, tokenB);

        // Assert that the pair address matches the factory pair address
        assertEq(pair, factoryPair);
    }

    function testFail_getPools_missingPair(bytes32 saltA, bytes32 saltB) public {
        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockERC20 tokenA = new MockERC20{salt: saltA}("Token A", "TKN_A");
        MockERC20 tokenB = new MockERC20{salt: saltB}("Token B", "TKN_B");

        // Call getPools() without having created the pair
        ButtonwoodLibrary.getPools(address(buttonswapFactory), address(tokenA), address(tokenB));
    }

    function test_getPools_emptyPair(bytes32 saltA, bytes32 saltB) public {
        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockERC20 tokenA = new MockERC20{salt: saltA}("Token A", "TKN_A");
        MockERC20 tokenB = new MockERC20{salt: saltB}("Token B", "TKN_B");

        // Create the pair with the factory and two tokens
        buttonswapFactory.createPair(address(tokenA), address(tokenB));

        // Call the getPools function to get the pools
        (uint256 poolA, uint256 poolB) =
            ButtonwoodLibrary.getPools(address(buttonswapFactory), address(tokenA), address(tokenB));

        // Assert that the pool amounts equal the token amounts minted
        assertEq(poolA, 0);
        assertEq(poolB, 0);
    }

    function test_getPools_nonEmptyPair(bytes32 saltA, bytes32 saltB, uint112 amountA, uint112 amountB) public {
        // Ensuring that amountA and amountB are enough to mint minimum liquidity
        vm.assume(amountA > 1000);
        vm.assume(amountB > 1000);

        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockERC20 tokenA = new MockERC20{salt: saltA}("Token A", "TKN_A");
        MockERC20 tokenB = new MockERC20{salt: saltB}("Token B", "TKN_B");

        // Create the pair with the factory and two tokens
        address pair = buttonswapFactory.createPair(address(tokenA), address(tokenB));

        // Minting liquidity in the pair
        tokenA.mint(address(this), amountA);
        tokenA.transfer(pair, amountA);
        tokenB.mint(address(this), amountB);
        tokenB.transfer(pair, amountB);
        ButtonswapPair(pair).mint(address(this));

        // Call the getPools function to get the pools
        (uint256 poolA, uint256 poolB) =
            ButtonwoodLibrary.getPools(address(buttonswapFactory), address(tokenA), address(tokenB));

        // Assert that the pool amounts equal the token amounts minted
        assertEq(poolA, amountA);
        assertEq(poolB, amountB);
    }

    function testFail_getReservoirs_missingPair(bytes32 saltA, bytes32 saltB) public {
        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockERC20 tokenA = new MockERC20{salt: saltA}("Token A", "TKN_A");
        MockERC20 tokenB = new MockERC20{salt: saltB}("Token B", "TKN_B");

        // Call getReservoirs() without having created the pair
        ButtonwoodLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));
    }

    function test_getReservoirs_emptyPair(bytes32 saltA, bytes32 saltB) public {
        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        // Create the pair with the factory and two tokens
        buttonswapFactory.createPair(address(tokenA), address(tokenB));

        // Call the getReservoirs function to get the reservoirs
        (uint256 reservoirA, uint256 reservoirB) =
            ButtonwoodLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));

        // Assert that the pool amounts equal the token amounts minted
        assertEq(reservoirA, 0);
        assertEq(reservoirB, 0);
    }

    function test_getReservoirs_nonEmptyPair(
        bytes32 saltA,
        bytes32 saltB,
        uint112 amountA,
        uint112 amountB,
        uint112 numerator,
        uint112 denominator
    ) public {
        // Ensuring that amountA and amountB are enough to mint minimum liquidity
        vm.assume(amountA > 1000);
        vm.assume(amountB > 1000);

        // Ensuring the rebase is valid and denominator is non-zero
        vm.assume(numerator != 0);
        vm.assume(denominator != 0);

        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        // Create the pair with the factory and two tokens
        address pair = buttonswapFactory.createPair(address(tokenA), address(tokenB));

        // First liquidity mint - determines price-ratios between the assets
        tokenA.mint(address(this), amountA);
        tokenA.transfer(pair, amountA);
        tokenB.mint(address(this), amountB);
        tokenB.transfer(pair, amountB);
        ButtonswapPair(pair).mint(address(this));

        // Rebasing tokenA
        tokenA.applyMultiplier(numerator, denominator);
        vm.assume((uint256(amountA) * numerator) / denominator < type(uint112).max);

        // Syncing the pair's pools & reservoirs
        ButtonswapPair(pair).sync();

        // Call the getReservoirs function to get the reservoirs
        (uint256 reservoirA, uint256 reservoirB) =
            ButtonwoodLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));

        // If the rebase is positive, reservoirA should be non-zero and reservoirB should be zero
        if (numerator > denominator) {
            assertApproxEqAbs(reservoirA, tokenA.balanceOf(pair) - amountA, 1);
            assertEq(reservoirB, 0);
        } else {
            // If the rebase is negative, reservoirA should be zero and reservoirB should be non-zero
            assertEq(reservoirA, 0);
            assertApproxEqAbs(reservoirB, amountB - (tokenA.balanceOf(pair) * amountB) / amountA, 1);
        }
    }

    function test_quote_zeroAmountA(uint256 poolA, uint256 poolB) public {
        uint256 amountA = 0;

        // Ensuring that pools are not empty
        vm.assume(poolA > 0);
        vm.assume(poolB > 0);

        vm.expectRevert(ButtonwoodLibrary.InsufficientAmount.selector);
        ButtonwoodLibrary.quote(amountA, poolA, poolB);
    }

    function test_quote_emptyPool(uint256 amountA, uint256 poolA, uint256 poolB) public {
        // Ensuring that amountA is non-zero
        vm.assume(amountA > 0);

        // Ensuring at least one pool is empty
        vm.assume(poolA == 0 || poolB == 0);

        vm.expectRevert(ButtonwoodLibrary.InsufficientLiquidity.selector);
        ButtonwoodLibrary.quote(amountA, poolA, poolB);
    }

    function test_quote_nonzeroValues(uint256 amountA, uint256 poolA, uint256 poolB) public {
        // Ensuring that amountA is non-zero
        vm.assume(amountA > 0);

        // Ensuring that pools are not empty
        vm.assume(poolA > 0);
        vm.assume(poolB > 0);

        // Ensuring that math does not overflow
        vm.assume(amountA < type(uint256).max / poolB);

        uint256 amountB = ButtonwoodLibrary.quote(amountA, poolA, poolB);

        // Assert that the amountB is correct
        assertEq(amountB, (amountA * poolB) / poolA);

        // Asserting that amountA/amountB = poolA/poolB
        // Since amountB is calculated with a rounded division from poolA, rounding error can be at most (poolA - 1)
        assertApproxEqAbs(amountA * poolB, amountB * poolA, poolA - 1);
    }

    function test_getAmountOut_zeroAmountIn(uint256 poolIn, uint256 poolOut) public {
        uint256 amountIn = 0;

        vm.expectRevert(ButtonwoodLibrary.InsufficientInputAmount.selector);
        ButtonwoodLibrary.getAmountOut(amountIn, poolIn, poolOut);
    }

    function test_getAmountOut_emptyPool(uint256 amountIn, uint256 poolIn, uint256 poolOut) public {
        // Ensuring that amountIn is non-zero
        vm.assume(amountIn > 0);

        // Ensuring at least one pool is empty
        vm.assume(poolIn == 0 || poolOut == 0);

        vm.expectRevert(ButtonwoodLibrary.InsufficientLiquidity.selector);
        ButtonwoodLibrary.getAmountOut(amountIn, poolIn, poolOut);
    }

    function test_getAmountOut_nonZeroValues(uint256 amountIn, uint256 poolIn, uint256 poolOut) public {
        // Ensuring that amountIn is non-zero
        vm.assume(amountIn > 0);

        // Ensuring that pools are not empty
        vm.assume(poolIn > 0);
        vm.assume(poolOut > 0);

        // Ensuring that math does not overflow
        vm.assume(amountIn < (type(uint256).max / 977) / poolOut);
        vm.assume(poolIn < (type(uint256).max / 1000) - amountIn);

        uint256 amountOut = ButtonwoodLibrary.getAmountOut(amountIn, poolIn, poolOut);

        // Assert that the amountOut is correct
        assertEq(amountOut, (poolOut * amountIn * 997) / (poolIn * 1000 + amountIn * 997));
    }

    function test_getAmountIn_zeroAmountOut(uint256 poolIn, uint256 poolOut) public {
        uint256 amountOut = 0;

        vm.expectRevert(ButtonwoodLibrary.InsufficientOutputAmount.selector);
        ButtonwoodLibrary.getAmountIn(amountOut, poolIn, poolOut);
    }

    function test_getAmountIn_emptyPool(uint256 amountOut, uint256 poolIn, uint256 poolOut) public {
        // Ensuring that amountOut is non-zero
        vm.assume(amountOut > 0);

        // Ensuring at least one pool is empty
        vm.assume(poolIn == 0 || poolOut == 0);

        vm.expectRevert(ButtonwoodLibrary.InsufficientLiquidity.selector);
        ButtonwoodLibrary.getAmountIn(amountOut, poolIn, poolOut);
    }

    function test_getAmountIn_nonZeroValues(uint256 amountOut, uint256 poolIn, uint256 poolOut) public {
        // Ensuring that amountIn is non-zero
        vm.assume(amountOut > 0);

        // Ensuring that pools are not empty
        vm.assume(poolIn > 0);
        vm.assume(poolOut > 0);

        // Ensuring that math does not have overflow/underflow/zero-denominator
        vm.assume(amountOut < (type(uint256).max / 1000) / poolIn);
        vm.assume(amountOut < poolOut);
        vm.assume(poolOut - amountOut < (type(uint256).max / 997));

        uint256 amountIn = ButtonwoodLibrary.getAmountIn(amountOut, poolIn, poolOut);

        // Assert that the amountIn is correct
        assertEq(amountIn, (poolIn * amountOut * 1000) / (997 * (poolOut - amountOut)) + 1);
    }

    function test_getAmountsOut_revertsOnEmptyPath(uint256 amountIn) public {
        vm.expectRevert(ButtonwoodLibrary.InvalidPath.selector);
        ButtonwoodLibrary.getAmountsOut(address(buttonswapFactory), amountIn, new address[](0));
    }

    function test_getAmountsOut_revertsOnSingletonPath(uint256 amountIn, address singlePathAddress) public {
        address[] memory path = new address[](1);
        path[0] = singlePathAddress;

        vm.expectRevert(ButtonwoodLibrary.InvalidPath.selector);
        ButtonwoodLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
    }

    function testFail_getAmountsOut_revertsOnPathWithUninitializedPair(
        uint256 amountIn,
        uint256 pathLengthSeed,
        uint256 missingPairIdxSeed
    ) public {
        // Setting path length to be between 2 and 10, with a missing pair at a random index
        uint256 pathLength = bound(pathLengthSeed, 2, 11);
        uint256 missingPairIdx = bound(missingPairIdxSeed, 0, pathLength - 2);

        // Creating all the tokens for the path
        address[] memory path = new address[](pathLength);
        for (uint256 idx = 0; idx < pathLength; idx++) {
            MockERC20 token = new MockERC20("Token", "TKN");
            path[idx] = address(token);
        }

        // Creating the path with the missing pair
        for (uint256 idx = 0; idx < pathLength - 1; idx++) {
            if (idx != missingPairIdx) {
                address pair = buttonswapFactory.createPair(path[idx], path[idx + 1]);
                MockERC20(path[idx]).mint(address(this), 10000);
                MockERC20(path[idx]).transfer(pair, 10000);
                MockERC20(path[idx + 1]).mint(address(this), 10000);
                MockERC20(path[idx + 1]).transfer(pair, 10000);
                ButtonswapPair(pair).mint(address(this));
            }
        }

        // Throws EvmError because there's a missing pair in the path
        ButtonwoodLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
    }

    function test_getAmountsOut_validPath(uint256 amountIn, uint256[] memory seedPoolOutAmounts) public {
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
            MockERC20 token = new MockERC20("Token", "TKN");
            path[idx] = address(token);
        }

        // Create the pairs and calculate expected amounts
        uint256[] memory expectedAmounts = new uint256[](path.length);
        expectedAmounts[0] = amountIn;
        for (uint256 idx; idx < path.length - 1; idx++) {
            address pair = buttonswapFactory.createPair(path[idx], path[idx + 1]);
            MockERC20(path[idx]).mint(address(this), 10000);
            MockERC20(path[idx]).transfer(pair, 10000);
            MockERC20(path[idx + 1]).mint(address(this), poolOutAmounts[idx + 1]);
            MockERC20(path[idx + 1]).transfer(pair, poolOutAmounts[idx + 1]);
            ButtonswapPair(pair).mint(address(this));
            expectedAmounts[idx + 1] = ButtonwoodLibrary.getAmountOut(expectedAmounts[idx], 10000, poolOutAmounts[idx + 1]);
        }

        uint256[] memory amounts = ButtonwoodLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
        assertEq(amounts, expectedAmounts, "Amounts out are not correct");
    }

    function test_getAmountsIn_revertsOnEmptyPath(uint256 amountOut) public {
        vm.expectRevert(ButtonwoodLibrary.InvalidPath.selector);
        ButtonwoodLibrary.getAmountsIn(address(buttonswapFactory), amountOut, new address[](0));
    }

    function test_getAmountsIn_revertsOnSingletonPath(uint256 amountOut, address singlePathAddress) public {
        address[] memory path = new address[](1);
        path[0] = singlePathAddress;

        vm.expectRevert(ButtonwoodLibrary.InvalidPath.selector);
        ButtonwoodLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);
    }

    function testFail_getAmountsIn_revertsOnPathWithUninitializedPair(
        uint256 amountOut,
        uint256 pathLengthSeed,
        uint256 missingPairIdxSeed
    ) public {
        // Setting path length to be between 2 and 10, with a missing pair at a random index
        uint256 pathLength = bound(pathLengthSeed, 2, 11);
        uint256 missingPairIdx = bound(missingPairIdxSeed, 0, pathLength - 2);

        // Creating all the tokens for the path
        address[] memory path = new address[](pathLength);
        for (uint256 idx = 0; idx < pathLength; idx++) {
            MockERC20 token = new MockERC20("Token", "TKN");
            path[idx] = address(token);
        }

        // Creating the path with the missing pair
        for (uint256 idx = 0; idx < pathLength - 1; idx++) {
            if (idx != missingPairIdx) {
                address pair = buttonswapFactory.createPair(path[idx], path[idx + 1]);
                MockERC20(path[idx]).mint(address(this), 10000);
                MockERC20(path[idx]).transfer(pair, 10000);
                MockERC20(path[idx + 1]).mint(address(this), 10000);
                MockERC20(path[idx + 1]).transfer(pair, 10000);
                ButtonswapPair(pair).mint(address(this));
            }
        }

        // Throws EvmError because there's a missing pair in the path
        ButtonwoodLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);
    }

    function test_getAmountsIn_validPath(uint256 amountOut, uint256[] memory seedPoolOutAmounts) public {
        // Ensuring that amountOut is bounded to avoid errors/overflows/underflows
        amountOut = bound(amountOut, 900, 1000); // 1000 * (1.1^10) < minimum pool out amount

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
            MockERC20 token = new MockERC20("Token", "TKN");
            path[idx] = address(token);
        }

        // Create the pairs and calculate expected amounts
        uint256[] memory expectedAmounts = new uint256[](path.length);
        expectedAmounts[expectedAmounts.length - 1] = amountOut;
        for (uint256 idx = path.length - 1; idx > 0; idx--) {
            address pair = buttonswapFactory.createPair(path[idx], path[idx - 1]);
            MockERC20(path[idx]).mint(address(this), poolOutAmounts[idx]);
            MockERC20(path[idx]).transfer(pair, poolOutAmounts[idx]);
            MockERC20(path[idx - 1]).mint(address(this), 10000);
            MockERC20(path[idx - 1]).transfer(pair, 10000);
            ButtonswapPair(pair).mint(address(this));
            expectedAmounts[idx - 1] = ButtonwoodLibrary.getAmountIn(expectedAmounts[idx], 10000, poolOutAmounts[idx]);
        }

        uint256[] memory amounts = ButtonwoodLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);
        assertEq(amounts, expectedAmounts, "Amounts out are not correct");
    }

    // Testing getAmountsOut vs getAmountsIn for random paths of length < 10 where price-steps are bounded [0.9, 1.1]
    function test_getAmountsOut_vsAmountsIn(uint256 amountIn, uint256[] memory seedPoolOutAmounts) public {
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
            // The pair-conversion rate will be bounded [0.9 , 1.1]
            poolOutAmounts[idx] = bound(poolOutAmounts[idx], 9000, 11000);
        }

        // Creating all the tokens for the path
        address[] memory path = new address[](poolOutAmounts.length);
        for (uint256 idx; idx < path.length; idx++) {
            MockERC20 token = new MockERC20("Token", "TKN");
            path[idx] = address(token);
        }

        // Create the pairs
        for (uint256 idx; idx < path.length - 1; idx++) {
            address pair = buttonswapFactory.createPair(path[idx], path[idx + 1]);
            MockERC20(path[idx]).mint(address(this), 10000);
            MockERC20(path[idx]).transfer(pair, 10000);
            MockERC20(path[idx + 1]).mint(address(this), poolOutAmounts[idx + 1]);
            MockERC20(path[idx + 1]).transfer(pair, poolOutAmounts[idx + 1]);
            ButtonswapPair(pair).mint(address(this));
        }

        uint256[] memory amountsForward = ButtonwoodLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
        uint256[] memory amountsBackward = ButtonwoodLibrary.getAmountsIn(address(buttonswapFactory), amountsForward[amountsForward.length - 1], path);

        for(uint256 idx = 0; idx < amountsForward.length; idx++) {
            assertApproxEqRel(amountsForward[idx], amountsBackward[idx], 0.05e18, "Amounts should be equal going both ways");
        }

    }
}
