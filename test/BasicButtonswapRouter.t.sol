// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IButtonswapRouterErrors} from "../src/interfaces/IButtonswapRouter/IButtonswapRouterErrors.sol";
import {BasicButtonswapRouter} from "../src/BasicButtonswapRouter.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {ButtonswapLibrary} from "../src/libraries/ButtonswapLibrary.sol";
import {PairMath} from "buttonswap-periphery_buttonswap-core/libraries/PairMath.sol";

contract BasicButtonswapRouterTest is Test, IButtonswapRouterErrors {
    uint256 constant BPS = 10_000;

    address public feeToSetter;
    uint256 public feeToSetterPrivateKey;
    address public isCreationRestrictedSetter;
    uint256 public isCreationRestrictedSetterPrivateKey;
    address public isPausedSetter;
    uint256 public isPausedSetterPrivateKey;
    address public paramSetter;
    uint256 public paramSetterPrivateKey;
    address public userA;
    uint256 public userAPrivateKey;
    MockRebasingERC20 public tokenA;
    MockRebasingERC20 public tokenB;
    ButtonswapFactory public buttonswapFactory;
    BasicButtonswapRouter public basicButtonswapRouter;

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

    // Utility function for testing functions that use Permit
    function generateUserAPermitSignature(IButtonswapPair pair, uint256 liquidity, uint256 deadline)
        private
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 permitDigest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                pair.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(pair.PERMIT_TYPEHASH(), userA, address(basicButtonswapRouter), liquidity, 0, deadline)
                )
            )
        );
        return vm.sign(userAPrivateKey, permitDigest);
    }

    function setUp() public {
        (feeToSetter, feeToSetterPrivateKey) = makeAddrAndKey("feeToSetter");
        (isCreationRestrictedSetter, isCreationRestrictedSetterPrivateKey) =
            makeAddrAndKey("isCreationRestrictedSetter");
        (isPausedSetter, isPausedSetterPrivateKey) = makeAddrAndKey("isPausedSetter");
        (paramSetter, paramSetterPrivateKey) = makeAddrAndKey("paramSetter");
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        tokenA = new MockRebasingERC20("TokenA", "TKNA", 18);
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);
        buttonswapFactory = new ButtonswapFactory(
            feeToSetter, isCreationRestrictedSetter, isPausedSetter, paramSetter, "LP Token", "LP"
        );
        basicButtonswapRouter = new BasicButtonswapRouter(address(buttonswapFactory));
    }

    function test_constructor() public {
        assertEq(basicButtonswapRouter.factory(), address(buttonswapFactory));
    }

    // **** createAndAddLiquidity() ****
    function test_createAndAddLiquidity_createsPairIfNoneExists(uint256 amountADesired, uint256 amountBDesired)
        public
    {
        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);

        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(basicButtonswapRouter), amountADesired);
        tokenB.approve(address(basicButtonswapRouter), amountBDesired);

        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Expect the factor to call createPair();
        vm.expectCall(
            address(buttonswapFactory), abi.encodeCall(ButtonswapFactory.createPair, (address(tokenA), address(tokenB)))
        );
        basicButtonswapRouter.createAndAddLiquidity(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, userA, block.timestamp + 1
        );

        // Asserting one pair has been created
        assertEq(buttonswapFactory.allPairsLength(), 1);

        // Asserting pair has the correct amount of tokens
        address pair = buttonswapFactory.getPair(address(tokenA), address(tokenB));
        assertEq(tokenA.balanceOf(pair), amountADesired);
        assertEq(tokenB.balanceOf(pair), amountBDesired);
    }

    function testFail_createAndAddLiquidity_pairAlreadyExists(uint256 amountADesired, uint256 amountBDesired) public {
        // Creating the pair with minimum liquidity before starting
        createAndInitializePair(tokenA, tokenB, 10000, 10000);

        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);

        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(basicButtonswapRouter), amountADesired);
        tokenB.approve(address(basicButtonswapRouter), amountBDesired);

        basicButtonswapRouter.createAndAddLiquidity(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, userA, block.timestamp + 1
        );
    }

    // **** addLiquidity() ****
    function testFail_addLiquidity_pairDoesNotExist(uint256 amountADesired, uint256 amountBDesired) public {
        // Minting enough for minimum liquidity requirement
        amountADesired = bound(amountADesired, 10000, type(uint112).max);
        amountBDesired = bound(amountBDesired, 10000, type(uint112).max);

        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(basicButtonswapRouter), amountADesired);
        tokenB.approve(address(basicButtonswapRouter), amountBDesired);

        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Attempt to add liquidity to a non-existent pair
        basicButtonswapRouter.addLiquidity(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, 700, userA, block.timestamp + 1
        );
    }

    function test_addLiquidity_pairExistsNoReservoirInsufficientAAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 amountADesired,
        uint112 amountBDesired,
        uint112 amountAMin
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // The calculated amount of B needed to match `amountADesired` needs to be greater than `amountBDesired` to calibrate with `amountADesired`
        vm.assume(amountADesired > 0);
        uint256 matchingBAmount = (amountADesired * poolB) / poolA;
        vm.assume(matchingBAmount > amountBDesired);

        // The calculated amount of A needed to match `amountBDesired` is less than `amountADesired`
        // but also being less than `amountAMin` triggers the error
        vm.assume(amountBDesired > 0);
        uint256 matchingAAmount = (amountBDesired * poolA) / poolB;

        vm.assume(matchingAAmount <= amountADesired);
        vm.assume(matchingAAmount < amountAMin);
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        basicButtonswapRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountADesired,
            amountBDesired,
            amountAMin,
            0,
            700,
            userA,
            block.timestamp + 1
        );
    }

    function test_addLiquidity_pairExistsInsufficientBAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 amountADesired,
        uint112 amountBDesired,
        uint112 amountBMin
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // The calculated amount of B needed to match `amountADesired` is less than `amountBDesired`
        // but also being less than `amountBMin` triggers the error
        vm.assume(amountADesired > 0);
        uint256 matchingBAmount = (uint256(amountADesired) * poolB) / poolA;
        vm.assume(matchingBAmount <= amountBDesired);
        vm.assume(matchingBAmount < amountBMin);

        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        basicButtonswapRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountADesired,
            amountBDesired,
            0,
            amountBMin,
            700,
            userA,
            block.timestamp + 1
        );
    }

    function test_addLiquidity_pairExistsNoReservoirAndOutputWithinBounds(
        uint256 poolA,
        uint256 poolB,
        uint112 amountADesired,
        uint112 amountBDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Making sure the bounds are sufficient
        uint112 amountAMin = 10000;
        uint112 amountBMin = 10000;

        // Setting up bounds to be properly ordered
        vm.assume(amountAMin < amountADesired);
        vm.assume(amountBMin < amountBDesired);

        // Ensuring the pair never has overflowing pool balances
        vm.assume(amountADesired < type(uint112).max - poolA);
        vm.assume(amountBDesired < type(uint112).max - poolB);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // The matching amount of either token must fit within the bounds
        uint256 matchingAAmount = (uint256(amountBDesired) * poolA) / poolB;
        uint256 matchingBAmount = (uint256(amountADesired) * poolB) / poolA;
        vm.assume(
            (matchingAAmount <= amountADesired && matchingAAmount > amountAMin)
                || (matchingBAmount <= amountBDesired && matchingBAmount > amountBMin)
        );

        // Approving the router to take at most amountADesired A tokens and at most amountBDesired B tokens
        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(basicButtonswapRouter), amountADesired);
        tokenB.approve(address(basicButtonswapRouter), amountBDesired);

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountA, uint256 amountB,) = basicButtonswapRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
            700,
            userA,
            block.timestamp + 1
        );

        // Assert that deposited amounts are within bounds
        assert(amountA > amountAMin && amountA <= amountADesired);
        assert(amountB > amountBMin && amountB <= amountBDesired);

        // Asserting that remaining tokens are returned to the caller
        assertEq(tokenA.balanceOf(address(this)), amountADesired - amountA);
        assertEq(tokenB.balanceOf(address(this)), amountBDesired - amountB);
    }

    function test_addLiquidity_pairExistsWithAReservoir(
        uint256 poolA,
        uint256 poolB,
        uint112 amountADesired,
        uint112 amountBDesired,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Ensuring that a A-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying the rebase
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Attempting to withdraw the amounts in the pool (because it was a positive rebase, poolA and poolB are unchanged, but resA has been created)
        amountADesired = uint112(poolA);
        amountBDesired = uint112(poolB);

        // Ensuring the pair never has overflowing pool balances
        vm.assume(amountADesired < type(uint112).max - poolA);
        vm.assume(amountBDesired < type(uint112).max - poolB);

        // Approving the router to take at most amountADesired A tokens and at most amountBDesired B tokens
        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(basicButtonswapRouter), amountADesired);
        tokenB.approve(address(basicButtonswapRouter), amountBDesired);

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountA, uint256 amountB,) = basicButtonswapRouter.addLiquidity(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, 700, userA, block.timestamp + 1
        );

        // Validating that it used amountADesired and scaled down to calculate how much B-token to use
        assertEq(amountA, amountADesired, "Router should have used amountADesired tokens");
        assertLt(amountB, amountBDesired, "Router should have scaled down the B-tokens it used");
    }

    function test_addLiquidity_pairExistsWithBReservoir(
        uint256 poolA,
        uint256 poolB,
        uint112 amountADesired,
        uint112 amountBDesired,
        uint256 rebaseNumerator,
        uint256 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Ensuring that a B-reservoir is created with a negative rebase on the A-tokens (greater than 1/2)
        rebaseDenominator = bound(rebaseDenominator, 2, type(uint8).max);
        rebaseNumerator = bound(rebaseNumerator, rebaseDenominator / 2, rebaseDenominator - 1);

        // Applying the rebase
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Attempting to withdraw the amounts in the pool (because it was a positive rebase, poolA and poolB are unchanged, but resA has been created)
        (uint256 newPoolA, uint256 newPoolB,,) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(tokenA), address(tokenB));
        amountADesired = uint112(newPoolA);
        amountBDesired = uint112(newPoolB);

        // Ensuring the pair never has overflowing pool balances
        vm.assume(amountADesired < type(uint112).max - poolA);
        vm.assume(amountBDesired < type(uint112).max - poolB);

        // Approving the router to take at most amountADesired A tokens and at most amountBDesired B tokens
        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(basicButtonswapRouter), amountADesired);
        tokenB.approve(address(basicButtonswapRouter), amountBDesired);

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountA, uint256 amountB,) = basicButtonswapRouter.addLiquidity(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, 700, userA, block.timestamp + 1
        );

        // Validating that it used amountBDesired and scaled down to calculate how much A-token to use
        assertLt(amountA, amountADesired, "Router should have scaled down the A-tokens it used");
        assertEq(amountB, amountBDesired, "Router should have used amountBDesired tokens");
    }

    function test_addLiquidity_movingAveragePriceOutOfBounds(
        bytes32 saltA,
        bytes32 saltB,
        uint256 poolA,
        uint256 poolB,
        uint256 swappedA
    ) public {
        // Re-assigning tokenA and tokenB to fuzz the order of the tokens
        tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);
        swappedA = bound(swappedA, poolA / 100, poolA - poolA / 100);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Do a swap to move the moving average price out of bounds
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        tokenA.mint(address(this), swappedA);
        tokenA.approve(address(basicButtonswapRouter), swappedA);
        basicButtonswapRouter.swapExactTokensForTokens(swappedA, 0, path, address(this), block.timestamp + 1);

        // Figuring out what the value of movingAveragePriceThresholdBps to use to guarantee movingAveragePrice0 exceeds valid range
        (uint256 newPoolA, uint256 newPoolB,,) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(tokenA), address(tokenB));

        uint16 movingAveragePrice0ThresholdBps;
        // Deriving the threshold by setting it to 1 under how much the deviation actually was
        //        (pool1/pool0) = newPool1/newPool0 * (mT + BPS)/(BPS)
        //        pool1 * newPool0 * BPS = newPool1 * (mT + BPS) * pool0
        //        (mT) = (pool1 * newPool0 * BPS)/(newPool1 * pool0) - BPS
        if (address(tokenA) < address(tokenB)) {
            // tokenA is token0
            vm.assume((poolB * newPoolA * BPS) > (newPoolB * poolA) * (BPS + 1));
            movingAveragePrice0ThresholdBps = uint16((poolB * newPoolA * BPS) / (newPoolB * poolA) - BPS - 1) - 1;
            vm.assume(0 < movingAveragePrice0ThresholdBps);
            vm.assume(movingAveragePrice0ThresholdBps < BPS);
        } else {
            // tokenB is token0
            vm.assume((poolA * newPoolB * BPS) > (newPoolA * poolB) * (BPS + 1));
            movingAveragePrice0ThresholdBps = uint16((poolA * newPoolB * BPS) / (newPoolA * poolB) - BPS - 1) - 1;
            vm.assume(0 < movingAveragePrice0ThresholdBps);
            vm.assume(movingAveragePrice0ThresholdBps < BPS);
        }

        // Approving the router to take at most newPoolA A tokens and at most newPoolB B tokens
        tokenA.mint(address(this), newPoolA);
        tokenB.mint(address(this), newPoolB);
        tokenA.approve(address(basicButtonswapRouter), newPoolA);
        tokenB.approve(address(basicButtonswapRouter), newPoolB);

        // Adding liquidity with the same balances that are currently in the pair
        vm.expectRevert(IButtonswapRouterErrors.MovingAveragePriceOutOfBounds.selector);
        basicButtonswapRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            newPoolA,
            newPoolB,
            0,
            0,
            movingAveragePrice0ThresholdBps,
            userA,
            block.timestamp + 1
        );
    }

    // **** addLiquidityWithReservoir() ****

    function test_addLiquidityWithReservoir_revertsIfNoPairExists(uint112 amountADesired, uint112 amountBDesired)
        public
    {
        // Minting enough for minimum liquidity requirement
        vm.assume(amountADesired > 10000);
        vm.assume(amountBDesired > 10000);

        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(basicButtonswapRouter), amountADesired);
        tokenB.approve(address(basicButtonswapRouter), amountBDesired);

        // Expect NoReservoir error to be thrown
        vm.expectRevert(IButtonswapRouterErrors.NoReservoir.selector);
        basicButtonswapRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_pairExistsButEmptyPools(uint112 amountADesired, uint112 amountBDesired)
        public
    {
        // Creating the pair without any liquidity
        buttonswapFactory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert(IButtonswapRouterErrors.NotInitialized.selector);
        basicButtonswapRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_pairExistsButMissingReservoir(
        uint256 poolA,
        uint256 poolB,
        uint112 amountADesired,
        uint112 amountBDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio. No rebase so no reservoir
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        vm.expectRevert(IButtonswapRouterErrors.NoReservoir.selector);
        basicButtonswapRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirAWithInsufficientAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 amountBDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Making sure amountBDesired is positive
        vm.assume(amountBDesired > 0);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Rebasing tokenA 10% up to create a tokenA reservoir
        tokenA.applyMultiplier(11, 10);

        // Calculating the optimalAmount of tokenA to amountBDesired and ensuring it's under `amountAMin`
        (, uint256 amountAOptimal) = ButtonswapLibrary.getMintSwappedAmounts(
            address(buttonswapFactory), address(tokenB), address(tokenA), amountBDesired
        );
        uint256 amountAMin = amountAOptimal + 1;

        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        basicButtonswapRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), 0, amountBDesired, amountAMin, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirAWithSufficientAmount(
        uint256 poolA,
        uint256 poolB,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountBDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolA < (type(uint112).max / rebaseNumerator) * rebaseDenominator);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Rebasing tokenA positively up to create a tokenA reservoir
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Getting reservoir size
        uint256 reservoirA;
        (poolA, poolB, reservoirA,) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(tokenA), address(tokenB));

        // Estimating how much of amountBDesired will be converted to A-tokens, and how much of the reservoir used
        uint256 liquidityOut;
        uint256 tokenBToSwap;
        uint256 swappedReservoirAmountA;
        (tokenBToSwap, swappedReservoirAmountA) = ButtonswapLibrary.getMintSwappedAmounts(
            address(buttonswapFactory), address(tokenB), address(tokenA), amountBDesired
        );

        // Making sure poolA doesn't get Overflowed
        vm.assume(poolA + swappedReservoirAmountA < type(uint112).max);
        // Making sure poolB doesn't get Overflowed
        vm.assume(poolB + amountBDesired < type(uint112).max);
        // Making sure reservoirA is not exceeded
        vm.assume(swappedReservoirAmountA < reservoirA);
        // Making sure the rest of reservoirA can absorb the ephemeral sync that happens from the tokenBToSwap transfer-in
        vm.assume((poolB + amountBDesired) * poolA <= (poolA + reservoirA) * poolB);

        // Estimating how much liquidity will be minted
        liquidityOut = PairMath.getDualSidedMintLiquidityOutAmount(
            pair.totalSupply(),
            swappedReservoirAmountA,
            amountBDesired - tokenBToSwap,
            poolA + reservoirA - swappedReservoirAmountA,
            poolB + tokenBToSwap
        );

        // Making sure minimum liquidity requirement is met
        vm.assume(liquidityOut > 0);
        // Making sure swappableReservoirLimit is not exceeded
        vm.assume(swappedReservoirAmountA < pair.getSwappableReservoirLimit());

        // Giving approval for amountBDesired tokenB
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(basicButtonswapRouter), amountBDesired);

        basicButtonswapRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), 0, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirBWithInsufficientAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 amountADesired
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Making sure amountADesired is positive
        vm.assume(amountADesired > 0);

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Rebasing tokenB 10% up to create a tokenB reservoir
        tokenB.applyMultiplier(11, 10);

        // Calculating the optimalAmount of tokenB to amountADesired and ensuring it's under `amountBMin`
        (, uint256 amountBOptimal) = ButtonswapLibrary.getMintSwappedAmounts(
            address(buttonswapFactory), address(tokenA), address(tokenB), amountADesired
        );
        uint256 amountBMin = amountBOptimal + 1;

        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        basicButtonswapRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, 0, 0, amountBMin, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirBWithSufficientAmount(
        uint256 poolA,
        uint256 poolB,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountADesired
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolB < (type(uint112).max / rebaseNumerator) * rebaseDenominator);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Rebasing tokenB positively up to create a tokenB reservoir
        tokenB.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Getting reservoir size
        uint256 reservoirB;
        (poolA, poolB,, reservoirB) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(tokenA), address(tokenB));

        // Estimating how much of amountADesired will be converted to B-tokens, and how much of the reservoir used
        uint256 liquidityOut;
        uint256 tokenAToSwap;
        uint256 swappedReservoirAmountB;
        (tokenAToSwap, swappedReservoirAmountB) = ButtonswapLibrary.getMintSwappedAmounts(
            address(buttonswapFactory), address(tokenA), address(tokenB), amountADesired
        );

        // Making sure poolB doesn't get Overflowed
        vm.assume(poolB + swappedReservoirAmountB < type(uint112).max);
        // Making sure poolA doesn't get Overflowed
        vm.assume(poolA + amountADesired < type(uint112).max);
        // Making sure reservoirB is not exceeded
        vm.assume(swappedReservoirAmountB < reservoirB);
        // Making sure the rest of reservoirB can absorb the ephemeral sync that happens from the tokenAToSwap transfer-in
        vm.assume((poolA + amountADesired) * poolB <= (poolB + reservoirB) * poolA);

        // Estimating how much liquidity will be minted
        liquidityOut = PairMath.getDualSidedMintLiquidityOutAmount(
            pair.totalSupply(),
            amountADesired - tokenAToSwap,
            swappedReservoirAmountB,
            poolA + tokenAToSwap,
            poolB + reservoirB - swappedReservoirAmountB
        );

        // Making sure minimum liquidity requirement is met
        vm.assume(liquidityOut > 0);
        // Making sure swappableReservoirLimit is not exceeded
        vm.assume(swappedReservoirAmountB < pair.getSwappableReservoirLimit());

        // Giving approval for amountADesired tokenA
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(basicButtonswapRouter), amountADesired);

        basicButtonswapRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, 0, 0, 0, userA, block.timestamp + 1
        );
    }

    // **** removeLiquidity() ****

    function testFail_removeLiquidity_pairDoesNotExist(uint256 liquidity) public {
        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Attempt to remove liquidity but will revert since it's calling `transferFrom()` on an invalid address
        basicButtonswapRouter.removeLiquidity(
            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidity_insufficientAAmount(uint256 poolA, uint256 poolB, uint112 liquidity) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolA > totalLiquidity);
        vm.assume(liquidity * poolB > totalLiquidity);

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = (liquidity * poolA) / (totalLiquidity) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(basicButtonswapRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        basicButtonswapRouter.removeLiquidity(
            address(tokenA), address(tokenB), liquidity, amountAMin, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidity_insufficientBAmount(uint256 poolA, uint256 poolB, uint112 liquidity) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolA > totalLiquidity);
        vm.assume(liquidity * poolB > totalLiquidity);

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = (liquidity * poolB) / (totalLiquidity) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(basicButtonswapRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        basicButtonswapRouter.removeLiquidity(
            address(tokenA), address(tokenB), liquidity, 0, amountBMin, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidity_sufficientAmounts(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolA > totalLiquidity);
        vm.assume(liquidity * poolB > totalLiquidity);

        // Calculating amountA and amountB to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountA = (liquidity * poolA) / (totalLiquidity);
        uint256 expectedAmountB = (liquidity * poolB) / (totalLiquidity);

        // Ensuring amountAMin and amountBMin are smaller than the amount of A and B that would be removed
        // Using bounds to reduce the number of vm assumptions needed
        amountAMin = bound(amountAMin, 0, expectedAmountA);
        amountBMin = bound(amountBMin, 0, expectedAmountB);

        // Giving permission to the pair to burn liquidity
        pair.approve(address(basicButtonswapRouter), liquidity);

        (uint256 amountA, uint256 amountB) = basicButtonswapRouter.removeLiquidity(
            address(tokenA), address(tokenB), liquidity, amountAMin, amountBMin, userA, block.timestamp + 1
        );

        // Ensuring amountA and amountB are as expected
        assertEq(amountA, expectedAmountA, "Did not remove expected amount of A");
        assertEq(amountB, expectedAmountB, "Did not remove expected amount of B");
    }

    // **** removeLiquidityFromReservoir() ****

    function testFail_removeLiquidityFromReservoir_pairDoesNotExist(uint256 liquidity) public {
        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Attempt to remove liquidity but will revert since it's calling `transferFrom()` on an invalid address
        basicButtonswapRouter.removeLiquidityFromReservoir(
            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityFromReservoir_insufficientAAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring that a A-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying a positive rebase to create an A-reservoir
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Calculating expectedAmountOutA and swappedReservoirAmountA
        (uint256 expectedAmountOutA, uint256 swappedReservoirAmountA) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(tokenA), address(tokenB), liquidity
        );

        // Ensuring `InsufficientLiquidityBurned()` error not thrown
        vm.assume(expectedAmountOutA > 0);

        // Ensuring swappedReservoirAmountA is less than the limit
        vm.assume(swappedReservoirAmountA < pair.getSwappableReservoirLimit());

        // Ensuring expectedAmountOutA is less than that of the reservoir
        (uint256 reservoirA,) =
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));
        vm.assume(expectedAmountOutA < reservoirA);

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = expectedAmountOutA + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(basicButtonswapRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        basicButtonswapRouter.removeLiquidityFromReservoir(
            address(tokenA), address(tokenB), liquidity, amountAMin, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityFromReservoir_insufficientBAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring that a B-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying a positive rebase to create an B-reservoir
        tokenB.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Calculating expectedAmountOutB and swappedReservoirAmountB
        (uint256 expectedAmountOutB, uint256 swappedReservoirAmountB) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(tokenB), address(tokenA), liquidity
        );

        // Ensuring `InsufficientLiquidityBurned()` error not thrown
        vm.assume(expectedAmountOutB > 0);

        // Ensuring swappedReservoirAmountB is less than the limit
        vm.assume(swappedReservoirAmountB < pair.getSwappableReservoirLimit());

        // Ensuring expectedAmountOutB is less than that of the reservoir
        (, uint256 reservoirB) =
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));
        vm.assume(expectedAmountOutB < reservoirB);

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = expectedAmountOutB + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(basicButtonswapRouter), liquidity);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        basicButtonswapRouter.removeLiquidityFromReservoir(
            address(tokenA), address(tokenB), liquidity, 0, amountBMin, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityFromReservoir_usingReservoirAWithSufficientAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring that a A-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying a positive rebase to create an A-reservoir
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Calculating expectedAmountOutA and swappedReservoirAmountA
        (uint256 expectedAmountOutA, uint256 swappedReservoirAmountA) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(tokenA), address(tokenB), liquidity
        );

        // Ensuring `InsufficientLiquidityBurned()` error not thrown
        vm.assume(expectedAmountOutA > 0);

        // Ensuring swappedReservoirAmountA is less than the limit
        vm.assume(swappedReservoirAmountA < pair.getSwappableReservoirLimit());

        // Ensuring expectedAmountOutA is less than that of the reservoir
        (uint256 reservoirA,) =
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));
        vm.assume(expectedAmountOutA < reservoirA);

        // Giving permission to the pair to burn liquidity
        pair.approve(address(basicButtonswapRouter), liquidity);

        (uint256 amountOutA, uint256 amountOutB) = basicButtonswapRouter.removeLiquidityFromReservoir(
            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1
        );

        // Checking that the correct amount of tokenA was removed and no tokenB was removed
        assertEq(amountOutA, expectedAmountOutA, "Incorrect amount of tokenA removed");
        assertEq(amountOutB, 0, "Incorrect amount of tokenB removed");
    }

    function test_removeLiquidityFromReservoir_usingReservoirBWithSufficientAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring that a B-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying a positive rebase to create an B-reservoir
        tokenB.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Calculating expectedAmountOutB and swappedReservoirAmountB
        (uint256 expectedAmountOutB, uint256 swappedReservoirAmountB) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(tokenB), address(tokenA), liquidity
        );

        // Ensuring `InsufficientLiquidityBurned()` error not thrown
        vm.assume(expectedAmountOutB > 0);

        // Ensuring swappedReservoirAmountB is less than the limit
        vm.assume(swappedReservoirAmountB < pair.getSwappableReservoirLimit());

        // Ensuring expectedAmountOutB is less than that of the reservoir
        (, uint256 reservoirB) =
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(tokenA), address(tokenB));
        vm.assume(expectedAmountOutB < reservoirB);

        // Giving permission to the pair to burn liquidity
        pair.approve(address(basicButtonswapRouter), liquidity);

        (uint256 amountOutA, uint256 amountOutB) = basicButtonswapRouter.removeLiquidityFromReservoir(
            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1
        );

        // Checking that the correct amount of tokenB was removed and no tokenA was removed
        assertEq(amountOutA, 0, "Incorrect amount of tokenA removed");
        assertEq(amountOutB, expectedAmountOutB, "Incorrect amount of tokenB removed");
    }

    // **** removeLiquidityWithPermit() ****
    // Note: Can't create permissions without an existing pair, so need to test against pairDoesNotExist case

    function test_removeLiquidityWithPermit_usingMaxPermissionButInsufficientAAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolA > totalLiquidity);
        vm.assume(liquidity * poolB > totalLiquidity);

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = (liquidity * poolA) / (totalLiquidity) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        basicButtonswapRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, amountAMin, 0, userA, block.timestamp + 1, true, v, r, s
        );
    }

    function test_removeLiquidityWithPermit_usingSpecificPermissionButInsufficientAAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolA > totalLiquidity);
        vm.assume(liquidity * poolB > totalLiquidity);

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = (liquidity * poolA) / (totalLiquidity) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        basicButtonswapRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, amountAMin, 0, userA, block.timestamp + 1, false, v, r, s
        );
    }

    function test_removeLiquidityWithPermit_usingMaxPermissionButInsufficientBAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolA > totalLiquidity);
        vm.assume(liquidity * poolB > totalLiquidity);

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = (liquidity * poolB) / (totalLiquidity) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        basicButtonswapRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, 0, amountBMin, userA, block.timestamp + 1, true, v, r, s
        );
    }

    function test_removeLiquidityWithPermit_usingSpecificPermissionButInsufficientBAmount(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolA > totalLiquidity);
        vm.assume(liquidity * poolB > totalLiquidity);

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = (liquidity * poolB) / (totalLiquidity) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        basicButtonswapRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, 0, amountBMin, userA, block.timestamp + 1, false, v, r, s
        );
    }

    function test_removeLiquidityWithPermit_usingMaxPermissionAndSufficientAmounts(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolA > totalLiquidity);
        vm.assume(liquidity * poolB > totalLiquidity);

        // Calculating amountA and amountB to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountA = (liquidity * poolA) / (totalLiquidity);
        uint256 expectedAmountB = (liquidity * poolB) / (totalLiquidity);

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.prank(userA);
        (uint256 amountA, uint256 amountB) = basicButtonswapRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1, true, v, r, s
        );

        // Ensuring amountA and amountB are as expected
        assertEq(amountA, expectedAmountA, "Did not remove expected amount of A");
        assertEq(amountB, expectedAmountB, "Did not remove expected amount of B");
    }

    function test_removeLiquidityWithPermit_usingSpecificPermissionAndSufficientAmounts(
        uint256 poolA,
        uint256 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolA = bound(poolA, 10000, type(uint112).max);
        poolB = bound(poolB, 10000, type(uint112).max);

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolA > totalLiquidity);
        vm.assume(liquidity * poolB > totalLiquidity);

        // Calculating amountA and amountB to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountA = (liquidity * poolA) / (totalLiquidity);
        uint256 expectedAmountB = (liquidity * poolB) / (totalLiquidity);

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.prank(userA);
        (uint256 amountA, uint256 amountB) = basicButtonswapRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1, false, v, r, s
        );

        // Ensuring amountA and amountB are as expected
        assertEq(amountA, expectedAmountA, "Did not remove expected amount of A");
        assertEq(amountB, expectedAmountB, "Did not remove expected amount of B");
    }

    // **** swapExactTokensForTokens() ****

    function test_swapExactTokensForTokens_insufficientOutputAmount(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] calldata seedPoolOutAmounts
    ) public {
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
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }

        // Create the pairs and populating the pools
        for (uint256 idx; idx < path.length - 1; idx++) {
            createAndInitializePair(
                MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx + 1]), 10000, poolOutAmounts[idx + 1]
            );
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);

        // Ensuring that the output is always less than amountOutMin
        amountOutMin = bound(amountOutMin, amounts[amounts.length - 1] + 1, type(uint256).max);

        // Expecting to revert with `InsufficientOutputAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientOutputAmount.selector);
        basicButtonswapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp + 1);
    }

    function test_swapExactTokensForTokens_sufficientOutputAmount(
        uint256 amountIn,
        uint256 amountOutMin,
        uint256[] calldata seedPoolOutAmounts
    ) public {
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
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }

        // Create the pairs and populating the pools
        for (uint256 idx; idx < path.length - 1; idx++) {
            createAndInitializePair(
                MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx + 1]), 10000, poolOutAmounts[idx + 1]
            );
        }

        uint256[] memory expectedAmounts = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);

        // Ensuring that amountOutMin is always less than the final output
        amountOutMin = bound(amountOutMin, 0, expectedAmounts[expectedAmounts.length - 1]);

        // Minting the first token to be approved and swapped
        MockRebasingERC20(path[0]).mint(address(this), amountIn);
        MockRebasingERC20(path[0]).approve(address(basicButtonswapRouter), amountIn);

        (uint256[] memory amounts) = basicButtonswapRouter.swapExactTokensForTokens(
            amountIn, amountOutMin, path, address(this), block.timestamp + 1
        );

        // Checking that the amounts in the trade are as expected
        assertEq(amounts, expectedAmounts, "Amounts in the trade are not as expected");

        // Checking that callee received the expected amount of the final token
        assertEq(
            MockRebasingERC20(path[path.length - 1]).balanceOf(address(this)),
            amounts[amounts.length - 1],
            "Did not receive expected amount of tokens"
        );
    }

    // **** swapTokensForExactTokens() ****

    function test_swapTokensForExactTokens_excessiveInputAmount(
        uint256 amountOut,
        uint256 amountInMax,
        uint256[] calldata seedPoolOutAmounts
    ) public {
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
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }

        // Create the pairs and calculate expected amounts
        for (uint256 idx = path.length - 1; idx > 0; idx--) {
            createAndInitializePair(
                MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx - 1]), poolOutAmounts[idx], 10000
            );
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);

        // Ensuring that the input is always greater than amountInMax
        amountInMax = bound(amountInMax, 0, amounts[0] - 1);

        // Expecting to revert with `ExcessiveInputAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.ExcessiveInputAmount.selector);
        basicButtonswapRouter.swapTokensForExactTokens(amountOut, amountInMax, path, address(this), block.timestamp + 1);
    }

    function test_swapTokensForExactTokens_nonExcessiveInputAmount(
        uint256 amountOut,
        uint256 amountInMax,
        uint256[] calldata seedPoolOutAmounts
    ) public {
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
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }

        // Create the pairs and calculate expected amounts
        for (uint256 idx = path.length - 1; idx > 0; idx--) {
            createAndInitializePair(
                MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx - 1]), poolOutAmounts[idx], 10000
            );
        }

        uint256[] memory expectedAmounts = ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);

        // Ensuring that the amountInMax is always greater than the input (but also don't want to trigger minting error)
        amountInMax = bound(amountInMax, expectedAmounts[0], type(uint112).max);

        // Minting the first token to be approved and swapped (with the amountInMax)
        MockRebasingERC20(path[0]).mint(address(this), amountInMax);
        MockRebasingERC20(path[0]).approve(address(basicButtonswapRouter), amountInMax);

        (uint256[] memory amounts) = basicButtonswapRouter.swapTokensForExactTokens(
            amountOut, amountInMax, path, address(this), block.timestamp + 1
        );

        // Checking that the amounts in the trade are as expected
        assertEq(amounts, expectedAmounts, "Amounts in the trade are not as expected");

        // Checking that correct amount of the first token was sent
        assertEq(
            MockRebasingERC20(path[0]).balanceOf(address(this)),
            amountInMax - expectedAmounts[0],
            "Sent more tokens than expected"
        );

        // Checking that correct amount of the last token was received
        assertEq(
            MockRebasingERC20(path[path.length - 1]).balanceOf(address(this)),
            amountOut,
            "Received less tokens than expected"
        );
    }
}
