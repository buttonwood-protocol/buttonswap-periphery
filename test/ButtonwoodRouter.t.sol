// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IButtonwoodRouterErrors} from "../src/interfaces/IButtonwoodRouter/IButtonwoodRouterErrors.sol";
import {ButtonwoodRouter} from "../src/ButtonwoodRouter.sol";
import {ButtonswapLibrary} from "../src/libraries/ButtonswapLibrary.sol";
import {IButtonswapPair} from "buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
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

    function test_constructor() public {
        assertEq(buttonwoodRouter.WETH(), wethAddress);
        assertEq(buttonwoodRouter.factory(), address(buttonswapFactory));
    }

    function test_receive_rejectNonWETHSender(uint256 ethAmount) public {
        // Sending ETH, ignoring data in return value
        (bool sent,) = payable(address(buttonwoodRouter)).call{value: ethAmount}("");
        assertTrue(!sent, "Expected call to fail");
    }

    function test_receive_acceptWETHSender(uint256 ethAmount) public {
        vm.deal(wethAddress, ethAmount);
        vm.prank(wethAddress);
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

        // Expect the factor to call createPair();
        vm.expectCall(
            address(buttonswapFactory), abi.encodeCall(ButtonswapFactory.createPair, (address(tokenA), address(tokenB)))
        );
        buttonwoodRouter.addLiquidity(
            address(tokenA), address(tokenB), amountADesired, amountBDesired, 0, 0, userA, block.timestamp + 1
        );

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
        vm.assume(amountAMin < amountADesired);
        vm.assume(amountBMin < amountBDesired);

        // Ensuring the pair never has overflowing pool balances
        vm.assume(amountADesired < type(uint112).max - poolA);
        vm.assume(amountBDesired < type(uint112).max - poolB);

        // Setting up bounds to be properly ordered
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
            address(tokenA), address(tokenB), amountADesired, amountBDesired, amountAMin, 0, userA, block.timestamp + 1
        );

        // Assert that deposited amounts are within bounds
        assert(amountA > amountAMin && amountA <= amountADesired);
        assert(amountB > amountBMin && amountB <= amountBDesired);

        // Asserting that remaining tokens are returned to the caller
        assert(tokenA.balanceOf(address(this)) == amountADesired - amountA);
        assert(tokenB.balanceOf(address(this)) == amountBDesired - amountB);
    }
}
