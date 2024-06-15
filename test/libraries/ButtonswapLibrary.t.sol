// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {ButtonswapLibrary} from "../../src/libraries/ButtonswapLibrary.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";
import {ButtonswapPair} from "buttonswap-periphery_buttonswap-core/ButtonswapPair.sol";
import {MockERC20} from "buttonswap-periphery_mock-contracts/MockERC20.sol";
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {PairMath} from "buttonswap-periphery_buttonswap-core/libraries/PairMath.sol";
import {console} from "buttonswap-periphery_forge-std/console.sol";

contract ButtonswapLibraryTest is Test {
    address public feeToSetter = 0x000000000000000000000000000000000000000A;
    address public isCreationRestrictedSetter = 0x000000000000000000000000000000000000000b;
    address public isPausedSetter = 0x000000000000000000000000000000000000000C;
    address public paramSetter = 0x000000000000000000000000000000000000000d;

    ButtonswapFactory public buttonswapFactory;

    // Utility function for creating and initializing pairs with poolA:poolB price ratio. Does not use ButtonwoodRouter
    function createAndInitializePair(MockERC20 tokenA, MockERC20 tokenB, uint256 poolA, uint256 poolB)
        private
        returns (ButtonswapPair pair)
    {
        pair = ButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.mint(address(this), poolA);
        tokenA.approve(address(pair), poolA);
        tokenB.mint(address(this), poolB);
        tokenB.approve(address(pair), poolB);

        if (pair.token0() == address(tokenA)) {
            pair.mint(poolA, poolB, address(this));
        } else {
            pair.mint(poolB, poolA, address(this));
        }
    }

    // Same utility function as `createAndInitializePair()` but for supporting MockRebasingERC20 tokens too
    function createAndInitializePairRebasing(
        MockRebasingERC20 tokenA,
        MockRebasingERC20 tokenB,
        uint256 poolA,
        uint256 poolB
    ) private returns (ButtonswapPair pair) {
        pair = ButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.mint(address(this), poolA);
        tokenA.approve(address(pair), poolA);
        tokenB.mint(address(this), poolB);
        tokenB.approve(address(pair), poolB);

        if (pair.token0() == address(tokenA)) {
            pair.mint(poolA, poolB, address(this));
        } else {
            pair.mint(poolB, poolA, address(this));
        }
    }

    function setUp() public {
        buttonswapFactory = new ButtonswapFactory(
            feeToSetter, isCreationRestrictedSetter, isPausedSetter, paramSetter, "LP Token", "LP"
        );
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
        (address token0, address token1) = ButtonswapLibrary.sortTokens(tokenA, tokenB);

        // Assert that the addresses are sorted correctly
        assertEq(token0, firstToken);
        assertEq(token1, secondToken);
    }

    function test_sortTokens_cannotCallWithIdenticalAddresses(address token) public {
        // Ensuring the IdenticalAddresses error is thrown
        vm.expectRevert(ButtonswapLibrary.IdenticalAddresses.selector);
        ButtonswapLibrary.sortTokens(token, token);
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
        vm.expectRevert(ButtonswapLibrary.ZeroAddress.selector);
        ButtonswapLibrary.sortTokens(tokenA, tokenB);
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
        address pair = ButtonswapLibrary.pairFor(address(buttonswapFactory), tokenA, tokenB);

        // Assert that the pair address matches the factory pair address
        assertEq(pair, factoryPair);
    }

    function testFail_getLiquidityBalances_missingPair(bytes32 saltA, bytes32 saltB) public {
        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockERC20 tokenA = new MockERC20{salt: saltA}("Token A", "TKN_A");
        MockERC20 tokenB = new MockERC20{salt: saltB}("Token B", "TKN_B");

        // Call getReservoirs() without having created the pair
        ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(tokenA), address(tokenB));
    }

    function test_getLiquidityBalances_emptyPair(bytes32 saltA, bytes32 saltB) public {
        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        // Create the pair with the factory and two tokens
        buttonswapFactory.createPair(address(tokenA), address(tokenB));

        // Call the getReservoirs function to get the reservoirs
        (uint256 poolA, uint256 poolB, uint256 reservoirA, uint256 reservoirB) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(tokenA), address(tokenB));

        // Assert that the liquidity balance amounts are empty
        assertEq(poolA, 0);
        assertEq(poolB, 0);
        assertEq(reservoirA, 0);
        assertEq(reservoirB, 0);
    }

    function test_getLiquidityBalances_nonEmptyPair(
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
        numerator = uint112(bound(numerator, 1, 1000));
        denominator = uint112(bound(denominator, 1, 1000));

        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        // Create the pair with the factory and two tokens
        // First liquidity mint - determines price-ratios between the assets
        address pair = address(createAndInitializePairRebasing(tokenA, tokenB, amountA, amountB));

        // Rebasing tokenA
        tokenA.applyMultiplier(numerator, denominator);
        vm.assume((uint256(amountA) * numerator) / denominator < type(uint112).max);

        // Call the getReservoirs function to get the reservoirs
        (uint256 poolA, uint256 poolB, uint256 reservoirA, uint256 reservoirB) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(tokenA), address(tokenB));

        // If the rebase is positive, reservoirA should be non-zero and reservoirB should be zero
        if (numerator > denominator) {
            assertEq(poolA, amountA); // PoolA should be unchanged
            assertEq(poolB, amountB); // PoolB should be unchanged
            assertApproxEqAbs(reservoirA, tokenA.balanceOf(pair) - amountA, 10); // ReservoirA created by surplus
            assertEq(reservoirB, 0); // ReservoirB untouched
        } else {
            // If the rebase is negative, reservoirA should be zero and reservoirB should be non-zero
            assertEq(poolA, tokenA.balanceOf(pair)); // PoolA decreased in size but holds entire amount
            assertApproxEqAbs(poolB, (tokenA.balanceOf(pair) * amountB) / amountA, amountA); // PoolB decreased in size
            assertEq(reservoirA, 0); // ReservoirA untouched
            assertApproxEqAbs(reservoirB, amountB - (tokenA.balanceOf(pair) * amountB) / amountA, 1); // ReservoirB created by deficit
        }
    }

    function testFail_getPools_missingPair(bytes32 saltA, bytes32 saltB) public {
        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockERC20 tokenA = new MockERC20{salt: saltA}("Token A", "TKN_A");
        MockERC20 tokenB = new MockERC20{salt: saltB}("Token B", "TKN_B");

        // Call getPools() without having created the pair
        ButtonswapLibrary.getPools(address(buttonswapFactory), address(tokenA), address(tokenB));
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
            ButtonswapLibrary.getPools(address(buttonswapFactory), address(tokenA), address(tokenB));

        // Assert that the pool amounts are empty
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
        // Minting liquidity in the pair
        createAndInitializePair(tokenA, tokenB, amountA, amountB);

        // Call the getPools function to get the pools
        (uint256 poolA, uint256 poolB) =
            ButtonswapLibrary.getPools(address(buttonswapFactory), address(tokenA), address(tokenB));

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
        ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));
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
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));

        // Assert that the reservoir amounts are empty
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
        numerator = uint112(bound(numerator, 1, 1000));
        denominator = uint112(bound(denominator, 1, 1000));

        // Creating the two tokens
        // Salts are used to fuzz unique addresses in arbitrary order
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        // Create the pair with the factory and two tokens
        // First liquidity mint - determines price-ratios between the assets
        address pair = address(createAndInitializePairRebasing(tokenA, tokenB, amountA, amountB));

        // Rebasing tokenA
        tokenA.applyMultiplier(numerator, denominator);
        vm.assume((uint256(amountA) * numerator) / denominator < type(uint112).max);

        // Call the getReservoirs function to get the reservoirs
        (uint256 reservoirA, uint256 reservoirB) =
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));

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

        vm.expectRevert(ButtonswapLibrary.InsufficientAmount.selector);
        ButtonswapLibrary.quote(amountA, poolA, poolB);
    }

    function test_quote_emptyPool(uint256 amountA, uint256 poolA, uint256 poolB) public {
        // Ensuring that amountA is non-zero
        vm.assume(amountA > 0);

        // Ensuring at least one pool is empty
        vm.assume(poolA == 0 || poolB == 0);

        vm.expectRevert(ButtonswapLibrary.InsufficientLiquidity.selector);
        ButtonswapLibrary.quote(amountA, poolA, poolB);
    }

    function test_quote_nonzeroValues(uint256 amountA, uint256 poolA, uint256 poolB) public {
        // Ensuring that amountA is non-zero
        vm.assume(amountA > 0);

        // Ensuring that pools are not empty
        vm.assume(poolA > 0);
        vm.assume(poolB > 0);

        // Ensuring that math does not overflow
        vm.assume(amountA < type(uint256).max / poolB);

        uint256 amountB = ButtonswapLibrary.quote(amountA, poolA, poolB);

        // Assert that the amountB is correct
        assertEq(amountB, (amountA * poolB) / poolA);

        // Asserting that amountA/amountB = poolA/poolB
        // Since amountB is calculated with a rounded division from poolA, rounding error can be at most (poolA - 1)
        assertApproxEqAbs(amountA * poolB, amountB * poolA, poolA - 1);
    }

    function test_getAmountOut_zeroAmountIn(uint256 poolIn, uint256 poolOut) public {
        uint256 amountIn = 0;

        vm.expectRevert(ButtonswapLibrary.InsufficientInputAmount.selector);
        ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut);
    }

    function test_getAmountOut_emptyPool(uint256 amountIn, uint256 poolIn, uint256 poolOut) public {
        // Ensuring that amountIn is non-zero
        vm.assume(amountIn > 0);

        // Ensuring at least one pool is empty
        vm.assume(poolIn == 0 || poolOut == 0);

        vm.expectRevert(ButtonswapLibrary.InsufficientLiquidity.selector);
        ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut);
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

        uint256 amountOut = ButtonswapLibrary.getAmountOut(amountIn, poolIn, poolOut);

        // Assert that the amountOut is correct
        assertEq(amountOut, (poolOut * amountIn * 997) / (poolIn * 1000 + amountIn * 997));
    }

    function test_getAmountIn_zeroAmountOut(uint256 poolIn, uint256 poolOut) public {
        uint256 amountOut = 0;

        vm.expectRevert(ButtonswapLibrary.InsufficientOutputAmount.selector);
        ButtonswapLibrary.getAmountIn(amountOut, poolIn, poolOut);
    }

    function test_getAmountIn_emptyPool(uint256 amountOut, uint256 poolIn, uint256 poolOut) public {
        // Ensuring that amountOut is non-zero
        vm.assume(amountOut > 0);

        // Ensuring at least one pool is empty
        vm.assume(poolIn == 0 || poolOut == 0);

        vm.expectRevert(ButtonswapLibrary.InsufficientLiquidity.selector);
        ButtonswapLibrary.getAmountIn(amountOut, poolIn, poolOut);
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

        uint256 numerator = poolIn * amountOut * 1000;
        uint256 denominator = (poolOut - amountOut) * 997;
        vm.assume(numerator < type(uint256).max - denominator + 1);

        uint256 amountIn = ButtonswapLibrary.getAmountIn(amountOut, poolIn, poolOut);

        // Assert that the amountIn is correct
        assertEq(amountIn, (poolIn * amountOut * 1000) / (997 * (poolOut - amountOut)) + 1);
    }

    function test_getAmountsOut_revertsOnEmptyPath(uint256 amountIn) public {
        vm.expectRevert(ButtonswapLibrary.InvalidPath.selector);
        ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, new address[](0));
    }

    function test_getAmountsOut_revertsOnSingletonPath(uint256 amountIn, address singlePathAddress) public {
        address[] memory path = new address[](1);
        path[0] = singlePathAddress;

        vm.expectRevert(ButtonswapLibrary.InvalidPath.selector);
        ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
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
                createAndInitializePair(MockERC20(path[idx]), MockERC20(path[idx + 1]), 10000, 10000);
            }
        }

        // Throws EvmError because there's a missing pair in the path
        ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
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
            MockERC20 token = new MockERC20("Token", "TKN");
            path[idx] = address(token);
        }

        // Create the pairs and calculate expected amounts
        uint256[] memory expectedAmounts = new uint256[](path.length);
        expectedAmounts[0] = amountIn;
        for (uint256 idx; idx < path.length - 1; idx++) {
            createAndInitializePair(MockERC20(path[idx]), MockERC20(path[idx + 1]), 10000, poolOutAmounts[idx + 1]);
            expectedAmounts[idx + 1] =
                ButtonswapLibrary.getAmountOut(expectedAmounts[idx], 10000, poolOutAmounts[idx + 1]);
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
        assertEq(amounts, expectedAmounts, "Amounts out are not correct");
    }

    function test_getAmountsIn_revertsOnEmptyPath(uint256 amountOut) public {
        vm.expectRevert(ButtonswapLibrary.InvalidPath.selector);
        ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, new address[](0));
    }

    function test_getAmountsIn_revertsOnSingletonPath(uint256 amountOut, address singlePathAddress) public {
        address[] memory path = new address[](1);
        path[0] = singlePathAddress;

        vm.expectRevert(ButtonswapLibrary.InvalidPath.selector);
        ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);
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
                createAndInitializePair(MockERC20(path[idx]), MockERC20(path[idx + 1]), 10000, 10000);
            }
        }

        // Throws EvmError because there's a missing pair in the path
        ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);
    }

    function test_getAmountsIn_validPath(uint256 amountOut, uint256[] calldata seedPoolOutAmounts) public {
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
            createAndInitializePair(MockERC20(path[idx]), MockERC20(path[idx - 1]), poolOutAmounts[idx], 10000);
            expectedAmounts[idx - 1] = ButtonswapLibrary.getAmountIn(expectedAmounts[idx], 10000, poolOutAmounts[idx]);
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);
        assertEq(amounts, expectedAmounts, "Amounts out are not correct");
    }

    // Testing getAmountsOut vs getAmountsIn for random paths of length < 10 where price-steps are bounded [0.9, 1.1]
    function test_getAmountsOut_vsAmountsIn(uint256 amountIn, uint256[] calldata seedPoolOutAmounts) public {
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
            createAndInitializePair(MockERC20(path[idx]), MockERC20(path[idx + 1]), 10000, poolOutAmounts[idx + 1]);
        }

        uint256[] memory amountsForward = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);
        uint256[] memory amountsBackward =
            ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountsForward[amountsForward.length - 1], path);

        for (uint256 idx = 0; idx < amountsForward.length; idx++) {
            assertApproxEqRel(
                amountsForward[idx], amountsBackward[idx], 0.05e18, "Amounts should be equal going both ways"
            );
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
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        // Creating the pair with poolA:poolB price ratio
        ButtonswapPair pair = createAndInitializePairRebasing(tokenA, tokenB, poolA, poolB);

        // Ensuring that a A-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying the rebase
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        uint256 totalSupply = pair.totalSupply();
        uint256 totalA = tokenA.balanceOf(address(pair));
        uint256 totalB = tokenB.balanceOf(address(pair));
        uint256 movingAveragePrice0 = pair.movingAveragePrice0();

        uint256 expectedSwappedReservoirAmountB;

        // tokenA == pair.token0
        if (address(tokenA) < address(tokenB)) {
            (, expectedSwappedReservoirAmountB) = PairMath.getSingleSidedMintLiquidityOutAmountA(
                totalSupply, amountInA, totalA, totalB, movingAveragePrice0
            );
        } else {
            // tokenB == pair.token0
            (, expectedSwappedReservoirAmountB) = PairMath.getSingleSidedMintLiquidityOutAmountB(
                totalSupply, amountInA, totalB, totalA, movingAveragePrice0
            );
        }
        (, uint256 swappedReservoirAmountB) = ButtonswapLibrary.getMintSwappedAmounts(
            address(buttonswapFactory), address(tokenA), address(tokenB), amountInA
        );

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
        MockRebasingERC20 tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        MockRebasingERC20 tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        // Creating the pair with poolA:poolB price ratio
        ButtonswapPair pair = createAndInitializePairRebasing(tokenA, tokenB, poolA, poolB);

        // Ensuring that a A-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying the rebase
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        uint256 totalSupply = pair.totalSupply();
        liquidity = bound(liquidity, 0, totalSupply);

        uint256 totalA = tokenA.balanceOf(address(pair));
        uint256 totalB = tokenB.balanceOf(address(pair));
        uint256 movingAveragePrice0 = pair.movingAveragePrice0();

        uint256 expectedTokenOutA;
        uint256 expectedSwappedReservoirAmountA;

        // tokenA == pair.token0
        if (address(tokenA) < address(tokenB)) {
            (expectedTokenOutA, expectedSwappedReservoirAmountA) =
                PairMath.getSingleSidedBurnOutputAmountA(totalSupply, liquidity, totalA, totalB, movingAveragePrice0);
        } else {
            // tokenB == pair.token0
            (expectedTokenOutA, expectedSwappedReservoirAmountA) =
                PairMath.getSingleSidedBurnOutputAmountB(totalSupply, liquidity, totalB, totalA, movingAveragePrice0);
        }

        (uint256 tokenOutA, uint256 swappedReservoirAmountA) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(tokenA), address(tokenB), liquidity
        );

        assertEq(tokenOutA, expectedTokenOutA, "tokenOutA should equal expectedTokenOutA");

        assertEq(
            swappedReservoirAmountA,
            expectedSwappedReservoirAmountA,
            "swappedReservoirAmountA should equal expectedSwappedReservoirAmountA"
        );
    }
}
