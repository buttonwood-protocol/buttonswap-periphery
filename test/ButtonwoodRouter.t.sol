// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IButtonwoodRouterErrors} from "../src/interfaces/IButtonwoodRouter/IButtonwoodRouterErrors.sol";
import {ButtonwoodRouter} from "../src/ButtonwoodRouter.sol";
import {IButtonswapPair} from "buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {MockRebasingERC20} from "mock-contracts/MockRebasingERC20.sol";
import {ButtonswapFactory} from "buttonswap-core/ButtonswapFactory.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {MockWeth} from "./mocks/MockWeth.sol";

contract ButtonwoodRouterTest is Test, IButtonwoodRouterErrors {
    address public userA = 0x000000000000000000000000000000000000000A;
    //    address public userB = 0x000000000000000000000000000000000000000b;
    //    address public userC = 0x000000000000000000000000000000000000000C;
    //    address public userD = 0x000000000000000000000000000000000000000d;

    MockRebasingERC20 public tokenA;
    MockRebasingERC20 public tokenB;
    IWETH public weth;
    ButtonswapFactory public buttonswapFactory;

    ButtonwoodRouter public buttonwoodRouter;

    // Required function for receiving ETH refunds
    receive() external payable {}

    function setUp() public {
        tokenA = new MockRebasingERC20("TokenA", "TKNA", 18);
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);
        weth = new MockWeth();
        buttonswapFactory = new ButtonswapFactory(userA);
        buttonwoodRouter = new ButtonwoodRouter(address(buttonswapFactory), address(weth));
    }

    function test_WETH() public {
        assertEq(buttonwoodRouter.WETH(), address(weth));
    }

    function test_factory() public {
        assertEq(buttonwoodRouter.factory(), address(buttonswapFactory));
    }

    function test_constructor() public {
        assertEq(buttonwoodRouter.WETH(), address(weth));
        assertEq(buttonwoodRouter.factory(), address(buttonswapFactory));
    }

    function test_receive_rejectNonWETHSender(uint256 ethAmount) public {
        // Sending ETH, ignoring data in return value
        (bool sent,) = payable(address(buttonwoodRouter)).call{value: ethAmount}("");
        assertTrue(!sent, "Expected call to fail");
    }

    function test_receive_acceptWETHSender(uint256 ethAmount) public {
        vm.deal(address(weth), ethAmount);
        vm.prank(address(weth));
        // Sending ETH, ignoring data in return value
        (bool sent,) = payable(address(buttonwoodRouter)).call{value: ethAmount}("");
        assertTrue(sent, "Expected call to succeed");
    }

    function test_addLiquidity_createsPairIfNoneExists(uint112 amountADesired, uint112 amountBDesired) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(amountADesired > 10000);
        vm.assume(amountBDesired > 10000);

        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(buttonwoodRouter), amountADesired);
        tokenB.approve(address(buttonwoodRouter), amountBDesired);

        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Expect the factor to call createPair();
        vm.expectCall(
            address(buttonswapFactory), abi.encodeCall(ButtonswapFactory.createPair, (address(tokenA), address(tokenB)))
        );
        buttonwoodRouter.addLiquidity(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, userA, block.timestamp + 1
        );

        // Asserting one pair has been created
        assertEq(buttonswapFactory.allPairsLength(), 1);
    }

    function test_addLiquidity_pairExistsInsufficientBAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 amountADesired,
        uint112 amountBDesired,
        uint112 amountBMin
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Creating the pair with poolA:poolB price ratio
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // The calculated amount of B needed to match `amountADesired` is less than `amountBDesired`
        // but also being less than `amountBMin` triggers the error
        vm.assume(amountADesired > 0);
        uint256 matchingBAmount = (uint256(amountADesired) * poolB) / poolA;
        vm.assume(matchingBAmount <= amountBDesired);
        vm.assume(matchingBAmount < amountBMin);

        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        buttonwoodRouter.addLiquidity(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, amountBMin, userA, block.timestamp + 1
        );
    }

    function test_addLiquidity_pairExistsInsufficientAAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 amountADesired,
        uint112 amountBDesired,
        uint112 amountAMin
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Creating the pair with poolA:poolB price ratio
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // The calculated amount of B needed to match `amountADesired` needs to be greater than `amountBDesired` to calibrate with `amountADesired`
        vm.assume(amountADesired > 0);
        uint256 matchingBAmount = (uint256(amountADesired) * poolB) / poolA;
        vm.assume(matchingBAmount > amountBDesired);

        // The calculated amount of A needed to match `amountBDesired` is less than `amountADesired`
        // but also being less than `amountAMin` triggers the error
        vm.assume(amountBDesired > 0);
        uint256 matchingAAmount = (uint256(amountBDesired) * poolA) / poolB;

        vm.assume(matchingAAmount <= amountADesired);
        vm.assume(matchingAAmount < amountAMin);
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        buttonwoodRouter.addLiquidity(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, amountAMin, 0, userA, block.timestamp + 1
        );
    }

    //ToDo: Ponder the case where amountBOptimal is chosen but is inferior to using amountBDesired
    function test_addLiquidity_pairExistsAndOutputWithinBounds(
        uint112 poolA,
        uint112 poolB,
        uint112 amountADesired,
        uint112 amountBDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Making sure the bounds are sufficient
        uint112 amountAMin = 10000;
        uint112 amountBMin = 10000;

        // Setting up bounds to be properly ordered
        vm.assume(amountAMin < amountADesired);
        vm.assume(amountBMin < amountBDesired);

        // Ensuring the pair never has overflowing pool balances
        vm.assume(amountADesired < type(uint112).max - poolA);
        vm.assume(amountBDesired < type(uint112).max - poolB);

        // Approving the router to spend the tokens
        tokenA.approve(address(buttonwoodRouter), amountADesired);
        tokenB.approve(address(buttonwoodRouter), amountBDesired);

        // Creating the pair with poolA:poolB price ratio
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

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
        tokenA.approve(address(buttonwoodRouter), amountADesired);
        tokenB.approve(address(buttonwoodRouter), amountBDesired);

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountA, uint256 amountB,) = buttonwoodRouter.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin,
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

    function test_addLiquidityWithReservoir_revertsIfNoPairExists(uint112 amountADesired, uint112 amountBDesired)
        public
    {
        // Minting enough for minimum liquidity requirement
        vm.assume(amountADesired > 10000);
        vm.assume(amountBDesired > 10000);

        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(buttonwoodRouter), amountADesired);
        tokenB.approve(address(buttonwoodRouter), amountBDesired);

        // Expect NoReservoir error to be thrown
        vm.expectRevert(IButtonwoodRouterErrors.NoReservoir.selector);
        buttonwoodRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_pairExistsButEmptyPools(
        uint112 poolA,
        uint112 poolB,
        uint112 amountADesired,
        uint112 amountBDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Creating the pair without any liquidity
        IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));

        vm.expectRevert(IButtonwoodRouterErrors.NotInitialized.selector);
        buttonwoodRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_pairExistsButMissingReservoir(
        uint112 poolA,
        uint112 poolB,
        uint112 amountADesired,
        uint112 amountBDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Creating the pair with poolA:poolB price ratio. No rebase so no reservoir
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        vm.expectRevert(IButtonwoodRouterErrors.NoReservoir.selector);
        buttonwoodRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirAWithInsufficientAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 amountBDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Making sure amountBDesired is positive
        vm.assume(amountBDesired > 0);

        // Creating the pair with poolA:poolB price ratio. No rebase so no reservoir
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenA 10% up to create a tokenA reservoir
        tokenA.applyMultiplier(11, 10);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Calculating a matching amount of tokenA to amountBDesired and ensuring it's under `amountAMin`
        uint256 matchingAAmount = (uint256(amountBDesired) * poolA) / poolB;
        uint256 amountAMin = matchingAAmount + 1;

        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        buttonwoodRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), 0, amountBDesired, amountAMin, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirAWithInsufficientReservoir(uint112 poolA, uint112 poolB)
        public
    {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Creating the pair with poolA:poolB price ratio. No rebase so no reservoir
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenA 10% up to create a tokenA reservoir
        tokenA.applyMultiplier(11, 10);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Calculating amountBDesired to be 2x more than the corresponding size of the reservoir
        // TokenA rebased up 10%, so 10% of poolB matches the tokenA reservoir. 20% is poolB / 5.
        uint256 amountBDesired = poolB / 5; // / 10 + 100000;

        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAReservoir.selector);
        buttonwoodRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), 0, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirAWithSufficientAmount(
        uint112 poolA,
        uint112 poolB,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountBDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolA < (type(uint112).max / rebaseNumerator) * rebaseDenominator);

        // Ensuring amountBDesired is between 0.01% and 100% of the reservoir, and that it doesn't cause overflow
        uint256 reservoirAInTermsOfB = (uint256(poolB) * (rebaseNumerator - rebaseDenominator)) / rebaseDenominator;
        vm.assume(amountBDesired > reservoirAInTermsOfB / 10000);
        vm.assume(amountBDesired < reservoirAInTermsOfB);
        vm.assume(amountBDesired < type(uint112).max / poolA);

        // Creating the pair with poolA:poolB price ratio. No rebase so no reservoir
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenA positively up to create a tokenA reservoir
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Giving approval for amountBDesired tokenB
        tokenB.mint(address(this), amountBDesired);
        tokenB.approve(address(buttonwoodRouter), amountBDesired);

        buttonwoodRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), 0, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirBWithInsufficientAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 amountADesired
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Making sure amountADesired is positive
        vm.assume(amountADesired > 0);

        // Creating the pair with poolA:poolB price ratio. No rebase so no reservoir
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenB 10% up to create a tokenA reservoir
        tokenB.applyMultiplier(11, 10);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Calculating a matching amount of tokenB to amountADesired and ensuring it's under `amountBMin`
        uint256 matchingBAmount = (uint256(amountADesired) * poolB) / poolA;
        uint256 amountBMin = matchingBAmount + 1;

        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        buttonwoodRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, 0, 0, amountBMin, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirBWithInsufficientReservoir(uint112 poolA, uint112 poolB)
        public
    {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Creating the pair with poolA:poolB price ratio. No rebase so no reservoir
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenB 10% up to create a tokenB reservoir
        tokenB.applyMultiplier(11, 10);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Calculating amountADesired to be 2x more than the corresponding size of the reservoir
        // TokenB rebased up 10%, so 10% of poolA matches the tokenB reservoir. 20% is poolA / 5.
        uint256 amountADesired = poolA / 5; // / 10 + 100000;

        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBReservoir.selector);
        buttonwoodRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, 0, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityWithReservoir_usingReservoirBWithSufficientAmount(
        uint112 poolA,
        uint112 poolB,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountADesired
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolB < (type(uint112).max / rebaseNumerator) * rebaseDenominator);

        // Ensuring amountADesired is between 0.01% and 100% of the reservoir, and that it doesn't cause overflow
        uint256 reservoirBInTermsOfA = (uint256(poolA) * (rebaseNumerator - rebaseDenominator)) / rebaseDenominator;
        vm.assume(amountADesired > reservoirBInTermsOfA / 10000);
        vm.assume(amountADesired < reservoirBInTermsOfA);
        vm.assume(amountADesired < type(uint112).max / poolB);

        // Creating the pair with poolA:poolB price ratio. No rebase so no reservoir
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenB positively up to create a tokenB reservoir
        tokenB.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Giving approval for amountADesired tokenA
        tokenA.mint(address(this), amountADesired);
        tokenA.approve(address(buttonwoodRouter), amountADesired);

        buttonwoodRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), amountADesired, 0, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETH_createsPairIfNoneExists(uint112 amountTokenDesired, uint112 amountETHSent) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(amountTokenDesired > 10000);
        vm.assume(amountETHSent > 10000);

        tokenA.mint(address(this), amountTokenDesired);
        tokenA.approve(address(buttonwoodRouter), amountTokenDesired);
        vm.deal(address(this), amountETHSent);

        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Expect the factor to call createPair();
        vm.expectCall(
            address(buttonswapFactory), abi.encodeCall(ButtonswapFactory.createPair, (address(tokenA), address(weth)))
        );
        buttonwoodRouter.addLiquidityETH{value: amountETHSent}(
            address(tokenA), amountTokenDesired, 0, 0, userA, block.timestamp + 1
        );

        // Asserting one pair has been created
        assertEq(buttonswapFactory.allPairsLength(), 1);
    }

    function test_addLiquidityETH_pairExistsInsufficientEthAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent,
        uint112 amountETHMin
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Creating the pair with poolToken:poolB price ratio
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // The calculated amount of ETH needed to match `amountTokenDesired` is less than `amountETHSent`
        // but also being less than `amountBMin` triggers the error
        vm.assume(amountTokenDesired > 0);
        uint256 matchingETHAmount = (uint256(amountTokenDesired) * poolETH) / poolToken;
        vm.assume(matchingETHAmount <= amountETHSent);
        vm.assume(matchingETHAmount < amountETHMin);

        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        buttonwoodRouter.addLiquidityETH{value: amountETHSent}(
            address(tokenA), amountTokenDesired, 0, amountETHMin, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETH_pairExistsInsufficientAAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent,
        uint112 amountTokenMin
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Creating the pair with poolToken:poolETH price ratio
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // The calculated amount of ETH needed to match `amountTokenDesired` needs to be greater than `amountETHSent` to calibrate with `amountTokenDesired`
        vm.assume(amountTokenDesired > 0);
        uint256 matchingETHAmount = (uint256(amountTokenDesired) * poolETH) / poolToken;
        vm.assume(matchingETHAmount > amountETHSent);

        // The calculated amount of token needed to match `amountETHSent` is less than `amountTokenDesired`
        // but also being less than `amountTokenMin` triggers the error
        vm.assume(amountETHSent > 0);
        uint256 matchingTokenAmount = (uint256(amountETHSent) * poolToken) / poolETH;

        vm.assume(matchingTokenAmount <= amountTokenDesired);
        vm.assume(matchingTokenAmount < amountTokenMin);

        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        buttonwoodRouter.addLiquidityETH{value: amountETHSent}(
            address(tokenA), amountTokenDesired, amountTokenMin, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETH_pairExistsAndOutputWithinBounds(
        uint112 poolToken,
        uint112 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Making sure the bounds are sufficient
        uint112 amountTokenMin = 10000;
        uint112 amountETHMin = 10000;

        // Setting up bounds to be properly ordered
        vm.assume(amountTokenMin < amountTokenDesired);
        vm.assume(amountETHMin < amountETHSent);

        // Ensuring the pair never has overflowing pool balances
        vm.assume(amountTokenDesired < type(uint112).max - poolToken);
        vm.assume(amountETHSent < type(uint112).max - poolETH);

        // Approving the router to spend the tokens
        tokenA.approve(address(buttonwoodRouter), amountTokenDesired);
        tokenB.approve(address(buttonwoodRouter), amountETHSent);

        // Creating the pair with poolToken:poolETH price ratio
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // The matching amount of either token must fit within the bounds
        uint256 matchingTokenAmount = (uint256(amountETHSent) * poolToken) / poolETH;
        uint256 matchingETHAmount = (uint256(amountTokenDesired) * poolETH) / poolToken;
        vm.assume(
            (matchingTokenAmount <= amountTokenDesired && matchingTokenAmount > amountTokenMin)
                || (matchingETHAmount <= amountETHSent && matchingETHAmount > amountETHMin)
        );

        // Approving the router to take at most amountTokenDesired A tokens and at most amountETHSent B tokens
        tokenA.mint(address(this), amountTokenDesired);
        tokenA.approve(address(buttonwoodRouter), amountTokenDesired);
        vm.deal(address(this), amountETHSent);
        uint256 ETHBalanceBefore = address(this).balance;

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountToken, uint256 amountETH,) = buttonwoodRouter.addLiquidityETH{value: amountETHSent}(
            address(tokenA), amountTokenDesired, amountTokenMin, amountETHMin, userA, block.timestamp + 1
        );

        // Assert that deposited amounts are within bounds
        assert(amountToken > amountTokenMin && amountToken <= amountTokenDesired);
        assert(amountETH > amountETHMin && amountETH <= amountETHSent);

        // Asserting that remaining tokens are returned to the caller
        assertEq(tokenA.balanceOf(address(this)), amountTokenDesired - amountToken);
        assertEq(address(this).balance, amountETHSent - amountETH, "Test contract should be refuned the remaining ETH");
    }
}
