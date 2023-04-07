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
import {ButtonswapLibrary} from "../src/libraries/ButtonswapLibrary.sol";
import {Babylonian} from "../src/libraries/Babylonian.sol";

contract ButtonwoodRouterTest is Test, IButtonwoodRouterErrors {
    address public userA;
    uint256 public userAPrivateKey;
    //    address public userB = 0x000000000000000000000000000000000000000b;
    //    address public userC = 0x000000000000000000000000000000000000000C;
    //    address public userD = 0x000000000000000000000000000000000000000d;

    MockRebasingERC20 public tokenA;
    MockRebasingERC20 public tokenB;
    IWETH public weth;
    ButtonswapFactory public buttonswapFactory;

    ButtonwoodRouter public buttonwoodRouter;

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
                keccak256(abi.encode(pair.PERMIT_TYPEHASH(), userA, address(buttonwoodRouter), liquidity, 0, deadline))
            )
        );
        return vm.sign(userAPrivateKey, permitDigest);
    }

    // Required function for receiving ETH refunds
    receive() external payable {}

    function setUp() public {
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
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

        // Creating the pair with poolA:poolB price ratio.
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

        // Creating the pair with poolA:poolB price ratio.
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

        // Ensuring amountBDesired is between 0.01% and 100% of the reservoir, and that it doesn't cause overflow, and enough liquidity is minted
        uint256 reservoirAInTermsOfB = (uint256(poolB) * (rebaseNumerator - rebaseDenominator)) / rebaseDenominator;
        vm.assume(amountBDesired > reservoirAInTermsOfB / 1000);
        vm.assume(amountBDesired < reservoirAInTermsOfB);
        vm.assume(amountBDesired < type(uint112).max / poolA);
        vm.assume(1000 * 2 * uint256(amountBDesired) > 2 * uint256(poolB) + reservoirAInTermsOfB);

        // Creating the pair with poolA:poolB price ratio.
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

        // Creating the pair with poolA:poolB price ratio.
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

        // Creating the pair with poolA:poolB price ratio.
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

        // Ensuring amountBDesired is between 0.01% and 100% of the reservoir, and that it doesn't cause overflow, and enough liquidity is minted
        uint256 reservoirBInTermsOfA = (uint256(poolA) * (rebaseNumerator - rebaseDenominator)) / rebaseDenominator;
        vm.assume(amountADesired > reservoirBInTermsOfA / 1000);
        vm.assume(amountADesired < reservoirBInTermsOfA);
        vm.assume(amountADesired < type(uint112).max / poolB);
        vm.assume(1000 * 2 * uint256(amountADesired) > 2 * uint256(poolA) + reservoirBInTermsOfA);

        // Creating the pair with poolA:poolB price ratio.
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

        // Creating the pair with poolToken:poolETH price ratio
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

    function test_addLiquidityETHWithReservoir_pairExistsButMissingReservoir(
        uint112 poolToken,
        uint112 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Creating the pair with poolToken:poolETH price ratio. No rebase so no reservoir
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonwoodRouterErrors.NoReservoir.selector);
        buttonwoodRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
            address(tokenA), amountTokenDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirTokenWithInsufficientAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 amountETHSent
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Making sure amountETHSent is positive
        vm.assume(amountETHSent > 0);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA 10% up to create a tokenA reservoir
        tokenA.applyMultiplier(11, 10);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Calculating a matching amount of tokenA to amountETHSent and ensuring it's under `amountTokenMin`
        uint256 matchingTokenAmount = (uint256(amountETHSent) * poolToken) / poolETH;
        uint256 amountTokenMin = matchingTokenAmount + 1;

        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        buttonwoodRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
            address(tokenA), 0, amountTokenMin, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirTokenWithInsufficientReservoir(
        uint112 poolToken,
        uint112 poolETH
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA 10% up to create a tokenA reservoir
        tokenA.applyMultiplier(11, 10);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Calculating amountETHSent to be 2x more than the corresponding size of the reservoir
        // TokenA rebased up 10%, so 10% of poolETH matches the tokenA reservoir. 20% is poolETH / 5.
        uint256 amountETHSent = poolETH / 5; // / 10 + 100000;

        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAReservoir.selector);
        buttonwoodRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
            address(tokenA), 0, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirTokenWithSufficientAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountETHSent
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolToken < (type(uint112).max / rebaseNumerator) * rebaseDenominator);

        // Ensuring amountETHSent is between 0.01% and 100% of the reservoir, and that it doesn't cause overflow, and enough liquidity is minted
        uint256 reservoirTokenInTermsOfETH =
            (uint256(poolETH) * (rebaseNumerator - rebaseDenominator)) / rebaseDenominator;
        vm.assume(amountETHSent > reservoirTokenInTermsOfETH / 10000);
        vm.assume(amountETHSent < reservoirTokenInTermsOfETH);
        vm.assume(amountETHSent < type(uint112).max / poolToken);
        vm.assume(10000 * amountETHSent > 2 * uint256(poolETH) + reservoirTokenInTermsOfETH);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA positively up to create a tokenA reservoir
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        vm.deal(address(this), amountETHSent);
        buttonwoodRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
            address(tokenA), 0, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirETHWithInsufficientAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 amountTokenDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Making sure amountTokenDesired is positive
        vm.assume(amountTokenDesired > 0);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA down 10% up to create an ETH reservoir (ETH can't rebase)
        tokenA.applyMultiplier(10, 11);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Fetching new pool balances to avoid rounding errors in the test
        // When you rebase down, you lose precision, so we refetch pool balances. Rebasing up doesn't have this problem.
        (uint256 newPoolToken, uint256 newPoolETH) =
            ButtonswapLibrary.getPools(address(buttonswapFactory), address(tokenA), address(weth));

        // Calculating a matching amount of ETH to amountTokenDesired and ensuring it's under `amountETHMin`
        uint256 matchingETHAmount = (amountTokenDesired * newPoolETH) / newPoolToken;
        uint256 amountETHMin = matchingETHAmount + 1;

        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        buttonwoodRouter.addLiquidityETHWithReservoir(
            address(tokenA), amountTokenDesired, 0, amountETHMin, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirETHWithInsufficientReservoir(
        uint112 poolToken,
        uint112 poolETH
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA 10% down to create an ETH reservoir (ETH can't rebase)
        tokenA.applyMultiplier(10, 11);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Calculating amountTokenDesired to be 2x more than the corresponding size of the reservoir
        // TokenB rebased up 10%, so 10% of poolToken matches the tokenB reservoir. 20% is poolToken / 5.
        uint256 amountTokenDesired = poolToken / 5; // / 10 + 100000;

        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBReservoir.selector);
        buttonwoodRouter.addLiquidityETHWithReservoir(
            address(tokenA), amountTokenDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirETHWithSufficientAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountTokenDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Ensuring it's a negative rebase that isn't too small (between 10% and 100%)
        rebaseDenominator = uint8(bound(rebaseDenominator, 100, type(uint8).max));
        rebaseNumerator = uint8(bound(rebaseNumerator, (uint256(rebaseDenominator) * 10) / 100, rebaseDenominator));

        // Ensuring amountTokenDesired is between 0.01% and 100% of the reservoir, that it doesn't cause overflow, and enough liquidity is minted
        uint256 reservoirETHInTermsOfA =
            (uint256(poolToken) * (rebaseDenominator - rebaseNumerator)) / rebaseDenominator;
        vm.assume(amountTokenDesired > reservoirETHInTermsOfA / 1000);
        vm.assume(amountTokenDesired < reservoirETHInTermsOfA);
        vm.assume(amountTokenDesired < type(uint112).max / poolETH);
        vm.assume(
            10000 * uint256(amountTokenDesired)
                > 2 * uint256(poolToken) * rebaseNumerator / rebaseDenominator + reservoirETHInTermsOfA
        );

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA negatively down to create an ETH reservoir (ETH can't rebase)
        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Syncing the pair to update the pools and reservoir
        pair.sync();

        // Giving approval for amountTokenDesired tokenA
        tokenA.mint(address(this), amountTokenDesired);
        tokenA.approve(address(buttonwoodRouter), amountTokenDesired);

        buttonwoodRouter.addLiquidityETHWithReservoir(
            address(tokenA), amountTokenDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidity_insufficientAAmount(uint112 poolA, uint112 poolB, uint112 liquidity) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolA);
        vm.assume(liquidity * poolA > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolB);
        vm.assume(liquidity * poolB > pairLiquidity + 1000);

        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = (liquidity * poolA) / (pairLiquidity + 1000) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        buttonwoodRouter.removeLiquidity(
            address(tokenA), address(tokenB), liquidity, amountAMin, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidity_insufficientBAmount(uint112 poolA, uint112 poolB, uint112 liquidity) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolA);
        vm.assume(liquidity * poolA > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolB);
        vm.assume(liquidity * poolB > pairLiquidity + 1000);

        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = (liquidity * poolB) / (pairLiquidity + 1000) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        buttonwoodRouter.removeLiquidity(
            address(tokenA), address(tokenB), liquidity, 0, amountBMin, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidity_sufficientAmounts(
        uint112 poolA,
        uint112 poolB,
        uint112 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolA);
        vm.assume(liquidity * poolA > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolB);
        vm.assume(liquidity * poolB > pairLiquidity + 1000);

        // Calculating amountA and amountB to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountA = (liquidity * poolA) / (pairLiquidity + 1000);
        uint256 expectedAmountB = (liquidity * poolB) / (pairLiquidity + 1000);

        // Ensuring amountAMin and amountBMin are smaller than the amount of A and B that would be removed
        // Using bounds to reduce the number of vm assumptions needed
        amountAMin = bound(amountAMin, 0, expectedAmountA);
        amountBMin = bound(amountBMin, 0, expectedAmountB);

        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        (uint256 amountA, uint256 amountB) = buttonwoodRouter.removeLiquidity(
            address(tokenA), address(tokenB), liquidity, amountAMin, amountBMin, userA, block.timestamp + 1
        );

        // Ensuring amountA and amountB are as expected
        assertEq(amountA, expectedAmountA, "Did not remove expected amount of A");
        assertEq(amountB, expectedAmountB, "Did not remove expected amount of B");
    }

    function test_removeLiquidityFromReservoir_insufficientAAmount(uint112 poolA, uint112 poolB, uint112 liquidity)
        public
    {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Calculating expected amount of tokenA to be removed, and ensuring it doesn't cause errors
        uint256 expectedAmountA = (liquidity * (uint256(poolA) * 21 / 10)) / (pairLiquidity + 1000);
        vm.assume(expectedAmountA > 0);
        vm.assume(expectedAmountA < poolA / 10); // reservoirA = 10% of poolA

        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenA up 10% and creating the tokenA reservoir
        tokenA.applyMultiplier(11, 10);
        pair.sync();

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = expectedAmountA + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        buttonwoodRouter.removeLiquidityFromReservoir(
            address(tokenA), address(tokenB), liquidity, amountAMin, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityFromReservoir_insufficientBAmount(uint112 poolA, uint112 poolB, uint112 liquidity)
        public
    {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Calculating expected amount of tokenB to be removed, and ensuring it doesn't cause errors
        uint256 expectedAmountB = (liquidity * (uint256(poolB) * 21 / 10)) / (pairLiquidity + 1000);
        vm.assume(expectedAmountB > 0);
        vm.assume(expectedAmountB < poolB / 10); // reservoirB = 10% of poolB

        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenB up 10% and creating the tokenA reservoir
        tokenB.applyMultiplier(11, 10);
        pair.sync();

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = expectedAmountB + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        buttonwoodRouter.removeLiquidityFromReservoir(
            address(tokenA), address(tokenB), liquidity, 0, amountBMin, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityFromReservoir_usingReservoirAWithSufficientAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 liquidity,
        uint256 positiveRebasePercentage
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);
        positiveRebasePercentage = bound(positiveRebasePercentage, 1, 100);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Calculating expected amount of tokenA to be removed, and ensuring it doesn't cause errors
        uint256 expectedAmountA =
            (liquidity * (uint256(poolA) * (200 + positiveRebasePercentage) / 100)) / (pairLiquidity + 1000);
        vm.assume(expectedAmountA > 0);
        vm.assume(expectedAmountA < (poolA * positiveRebasePercentage) / 100);

        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenA up `positiveRebasePercentage`% and creating the tokenA reservoir
        tokenA.applyMultiplier(100 + positiveRebasePercentage, 100);
        pair.sync();

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Removing liquidity from the reservoir
        (uint256 amountA, uint256 amountB) = buttonwoodRouter.removeLiquidityFromReservoir(
            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1
        );

        // Checking that the correct amount of tokenA was removed and no tokenB was removed
        assertEq(amountA, expectedAmountA, "Incorrect amount of tokenA removed");
        assertEq(amountB, 0, "Incorrect amount of tokenB removed");
    }

    function test_removeLiquidityFromReservoir_usingReservoirBWithSufficientAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 liquidity,
        uint256 positiveRebasePercentage
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);
        positiveRebasePercentage = bound(positiveRebasePercentage, 1, 100);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Calculating expected amount of tokenB to be removed, and ensuring it doesn't cause errors
        uint256 expectedAmountB =
            (liquidity * (uint256(poolB) * (200 + positiveRebasePercentage) / 100)) / (pairLiquidity + 1000);
        vm.assume(expectedAmountB > 0);
        vm.assume(expectedAmountB < (poolB * positiveRebasePercentage) / 100);

        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(address(this), poolA);
        tokenB.mint(address(this), poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(address(this));

        // Rebasing tokenB up `positiveRebasePercentage`% and creating the tokenB reservoir
        tokenB.applyMultiplier(100 + positiveRebasePercentage, 100);
        pair.sync();

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Removing liquidity from the reservoir
        (uint256 amountA, uint256 amountB) = buttonwoodRouter.removeLiquidityFromReservoir(
            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1
        );

        // Checking that the correct amount of tokenB was removed and no tokenA was removed
        assertEq(amountA, 0, "Incorrect amount of tokenA removed");
        assertEq(amountB, expectedAmountB, "Incorrect amount of tokenB removed");
    }

    function test_removeLiquidityETH_insufficientAAmount(uint112 poolToken, uint112 poolETH, uint112 liquidity)
        public
    {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolToken);
        vm.assume(liquidity * poolToken > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolETH);
        vm.assume(liquidity * poolETH > pairLiquidity + 1000);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Calculating amountTokenMin to be one more than the amount of A that would be removed
        uint256 amountTokenMin = (liquidity * poolToken) / (pairLiquidity + 1000) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        buttonwoodRouter.removeLiquidityETH(address(tokenA), liquidity, amountTokenMin, 0, userA, block.timestamp + 1);
    }

    function test_removeLiquidityETH_insufficientBAmount(uint112 poolToken, uint112 poolETH, uint112 liquidity)
        public
    {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolToken);
        vm.assume(liquidity * poolToken > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolETH);
        vm.assume(liquidity * poolETH > pairLiquidity + 1000);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Calculating amountETHMin to be one more than the amount of B that would be removed
        uint256 amountETHMin = (liquidity * poolETH) / (pairLiquidity + 1000) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        buttonwoodRouter.removeLiquidityETH(address(tokenA), liquidity, 0, amountETHMin, userA, block.timestamp + 1);
    }

    function test_removeLiquidityETH_sufficientAmounts(
        uint112 poolToken,
        uint112 poolETH,
        uint112 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Calculating amount of liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolToken);
        vm.assume(liquidity * poolToken > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolETH);
        vm.assume(liquidity * poolETH > pairLiquidity + 1000);

        // Calculating amountToken and amountETH to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountToken = (liquidity * poolToken) / (pairLiquidity + 1000);
        uint256 expectedAmountETH = (liquidity * poolETH) / (pairLiquidity + 1000);

        // Ensuring amountTokenMin and amountETHMin are smaller than the amount of A and B that would be removed
        // Using bounds to reduce the number of vm assumptions needed
        amountTokenMin = bound(amountTokenMin, 0, expectedAmountToken);
        amountETHMin = bound(amountETHMin, 0, expectedAmountETH);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        (uint256 amountToken, uint256 amountETH) = buttonwoodRouter.removeLiquidityETH(
            address(tokenA), liquidity, amountTokenMin, amountETHMin, userA, block.timestamp + 1
        );

        // Ensuring amountToken and amountETH are as expected
        assertEq(amountToken, expectedAmountToken, "Did not remove expected amount of A");
        assertEq(amountETH, expectedAmountETH, "Did not remove expected amount of B");
    }

    function test_removeLiquidityETHFromReservoir_insufficientAAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Calculating expected amount of tokenA to be removed, and ensuring it doesn't cause errors
        uint256 expectedAmountToken = (liquidity * (uint256(poolToken) * 21 / 10)) / (pairLiquidity + 1000);
        vm.assume(expectedAmountToken > 0);
        vm.assume(expectedAmountToken < poolToken / 10); // reservoirA = 10% of poolToken

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA up 10% and creating the tokenA reservoir
        tokenA.applyMultiplier(11, 10);
        pair.sync();

        // Calculating amountTokenMin to be one more than the amount of A that would be removed
        uint256 amountTokenMin = expectedAmountToken + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        buttonwoodRouter.removeLiquidityETHFromReservoir(
            address(tokenA), liquidity, amountTokenMin, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityETHFromReservoir_insufficientBAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Calculating expected amount of tokenB to be removed, and ensuring it doesn't cause errors
        uint256 newPoolToken = (uint256(poolToken) * (100 - 10)) / 100;
        uint256 newPoolETH = newPoolToken * poolETH / poolToken;
        uint256 newReservoirETH = poolETH - newPoolETH;
        uint256 expectedAmountETH = (liquidity * (newReservoirETH + newPoolETH + newPoolETH)) / (pairLiquidity + 1000);
        vm.assume(expectedAmountETH > 0);
        vm.assume(expectedAmountETH < poolETH / 10); // reservoirB = 10% of poolETH

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA 10% down to create an ETH reservoir (ETH can't rebase)
        tokenA.applyMultiplier(9, 10);
        pair.sync();

        // Calculating amountETHMin to be two more than the amount of A that would be removed
        // +2 instead of +1 because rebasing down causes additional rounding errors the math
        uint256 amountETHMin = expectedAmountETH + 2;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        buttonwoodRouter.removeLiquidityETHFromReservoir(
            address(tokenA), liquidity, 0, amountETHMin, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityETHFromReservoir_usingReservoirAWithSufficientAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 liquidity,
        uint256 positiveRebasePercentage
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);
        positiveRebasePercentage = bound(positiveRebasePercentage, 1, 100);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Calculating expected amount of tokenA to be removed, and ensuring it doesn't cause errors
        uint256 expectedAmountToken =
            (liquidity * (uint256(poolToken) * (200 + positiveRebasePercentage) / 100)) / (pairLiquidity + 1000);
        vm.assume(expectedAmountToken > 0);
        vm.assume(expectedAmountToken < (poolToken * positiveRebasePercentage) / 100);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA up `positiveRebasePercentage`% and creating the tokenA reservoir
        tokenA.applyMultiplier(100 + positiveRebasePercentage, 100);
        pair.sync();

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Removing liquidity from the reservoir
        (uint256 amountToken, uint256 amountETH) = buttonwoodRouter.removeLiquidityETHFromReservoir(
            address(tokenA), liquidity, 0, 0, userA, block.timestamp + 1
        );

        // Checking that the correct amount of tokenA was removed and no ETH was removed
        assertEq(amountToken, expectedAmountToken, "Incorrect amount of tokenA removed");
        assertEq(amountETH, 0, "Incorrect amount of ETH removed");
    }

    function test_removeLiquidityETHFromReservoir_usingReservoirBWithSufficientAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 liquidity,
        uint256 negativeRebasePercentage
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);
        negativeRebasePercentage = bound(negativeRebasePercentage, 1, 99);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Calculating expected amount of ETH to be removed, and ensuring it doesn't cause errors
        uint256 newPoolToken = (poolToken * (100 - negativeRebasePercentage)) / 100;
        uint256 newPoolETH = newPoolToken * poolETH / poolToken;
        uint256 newReservoirETH = poolETH - newPoolETH;
        uint256 expectedAmountETH = (liquidity * (newReservoirETH + newPoolETH + newPoolETH)) / (pairLiquidity + 1000);

        vm.assume(expectedAmountETH > 0);
        vm.assume(expectedAmountETH < (poolETH * negativeRebasePercentage) / 100);

        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(address(this), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(address(this));

        // Rebasing tokenA down `negativeRebasePercentage`% and creating the ETH reservoir (ETH can't rebase)
        tokenA.applyMultiplier(100 - negativeRebasePercentage, 100);
        pair.sync();

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonwoodRouter), liquidity);

        // Removing liquidity from the reservoir
        (uint256 amountToken, uint256 amountETH) = buttonwoodRouter.removeLiquidityETHFromReservoir(
            address(tokenA), liquidity, 0, 0, userA, block.timestamp + 1
        );

        // Checking that the correct amount of ETH was removed and no token A was removed
        assertEq(amountToken, 0, "Incorrect amount of tokenA removed");
        assertApproxEqAbs(amountETH, expectedAmountETH, 1);
    }

    function test_removeLiquidityWithPermit_usingMaxPermissionButInsufficientAAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolA);
        vm.assume(liquidity * poolA > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolB);
        vm.assume(liquidity * poolB > pairLiquidity + 1000);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(userA, poolA);
        tokenB.mint(userA, poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(userA);
        vm.stopPrank();

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = (liquidity * poolA) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        buttonwoodRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, amountAMin, 0, userA, block.timestamp + 1, true, v, r, s
        );
    }

    function test_removeLiquidityWithPermit_usingSpecificPermissionButInsufficientAAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolA);
        vm.assume(liquidity * poolA > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolB);
        vm.assume(liquidity * poolB > pairLiquidity + 1000);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(userA, poolA);
        tokenB.mint(userA, poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(userA);
        vm.stopPrank();

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = (liquidity * poolA) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        buttonwoodRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, amountAMin, 0, userA, block.timestamp + 1, false, v, r, s
        );
    }

    function test_removeLiquidityWithPermit_usingMaxPermissionButInsufficientBAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolA);
        vm.assume(liquidity * poolA > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolB);
        vm.assume(liquidity * poolB > pairLiquidity + 1000);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(userA, poolA);
        tokenB.mint(userA, poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(userA);
        vm.stopPrank();

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = (liquidity * poolB) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        buttonwoodRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, 0, amountBMin, userA, block.timestamp + 1, true, v, r, s
        );
    }

    function test_removeLiquidityWithPermit_usingSpecificPermissionButInsufficientBAmount(
        uint112 poolA,
        uint112 poolB,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolA);
        vm.assume(liquidity * poolA > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolB);
        vm.assume(liquidity * poolB > pairLiquidity + 1000);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(userA, poolA);
        tokenB.mint(userA, poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(userA);
        vm.stopPrank();

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = (liquidity * poolB) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        buttonwoodRouter.removeLiquidityWithPermit(
            address(tokenA), address(tokenB), liquidity, 0, amountBMin, userA, block.timestamp + 1, false, v, r, s
        );
    }

    function test_removeLiquidityWithPermit_usingMaxPermissionAndSufficientAmounts(
        uint112 poolA,
        uint112 poolB,
        uint112 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolA);
        vm.assume(liquidity * poolA > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolB);
        vm.assume(liquidity * poolB > pairLiquidity + 1000);

        // Calculating amountA and amountB to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountA = (liquidity * poolA) / (pairLiquidity + 1000);
        uint256 expectedAmountB = (liquidity * poolB) / (pairLiquidity + 1000);

        // Ensuring amountAMin and amountBMin are smaller than the amount of A and B that would be removed
        // Using bounds to reduce the number of vm assumptions needed
        amountAMin = bound(amountAMin, 0, expectedAmountA);
        amountBMin = bound(amountBMin, 0, expectedAmountB);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(userA, poolA);
        tokenB.mint(userA, poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(userA);
        vm.stopPrank();

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        vm.prank(userA);
        (uint256 amountA, uint256 amountB) = buttonwoodRouter.removeLiquidityWithPermit(
            address(tokenA),
            address(tokenB),
            liquidity,
            amountAMin,
            amountBMin,
            userA,
            block.timestamp + 1,
            true,
            v,
            r,
            s
        );

        // Ensuring amountA and amountB are as expected
        assertEq(amountA, expectedAmountA, "Did not remove expected amount of A");
        assertEq(amountB, expectedAmountB, "Did not remove expected amount of B");
    }

    function test_removeLiquidityWithPermit_usingSpecificPermissionAndSufficientAmounts(
        uint112 poolA,
        uint112 poolB,
        uint112 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolA > 10000);
        vm.assume(poolB > 10000);

        // Calculating amount of liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolA);
        vm.assume(liquidity * poolA > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolB);
        vm.assume(liquidity * poolB > pairLiquidity + 1000);

        // Calculating amountA and amountB to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountA = (liquidity * poolA) / (pairLiquidity + 1000);
        uint256 expectedAmountB = (liquidity * poolB) / (pairLiquidity + 1000);

        // Ensuring amountAMin and amountBMin are smaller than the amount of A and B that would be removed
        // Using bounds to reduce the number of vm assumptions needed
        amountAMin = bound(amountAMin, 0, expectedAmountA);
        amountBMin = bound(amountBMin, 0, expectedAmountB);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolA:poolB price ratio.
        tokenA.mint(userA, poolA);
        tokenB.mint(userA, poolB);
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(tokenB)));
        tokenA.transfer(address(pair), poolA);
        tokenB.transfer(address(pair), poolB);
        pair.mint(userA);
        vm.stopPrank();

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        vm.prank(userA);
        (uint256 amountA, uint256 amountB) = buttonwoodRouter.removeLiquidityWithPermit(
            address(tokenA),
            address(tokenB),
            liquidity,
            amountAMin,
            amountBMin,
            userA,
            block.timestamp + 1,
            false,
            v,
            r,
            s
        );

        // Ensuring amountA and amountB are as expected
        assertEq(amountA, expectedAmountA, "Did not remove expected amount of A");
        assertEq(amountB, expectedAmountB, "Did not remove expected amount of B");
    }

    function test_removeLiquidityETHWithPermit_insufficientAAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 liquidity,
        bool maxPermission
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolToken);
        vm.assume(liquidity * poolToken > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolETH);
        vm.assume(liquidity * poolETH > pairLiquidity + 1000);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(userA, poolToken);
        vm.deal(userA, poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(userA);
        vm.stopPrank();

        // Calculating amountTokenMin to be one more than the amount of A that would be removed
        uint256 amountTokenMin = (liquidity * poolToken) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) =
            generateUserAPermitSignature(pair, maxPermission ? type(uint256).max : liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        buttonwoodRouter.removeLiquidityETHWithPermit(
            address(tokenA), liquidity, amountTokenMin, 0, userA, block.timestamp + 1, maxPermission, v, r, s
        );
    }

    function test_removeLiquidityETHWithPermit_insufficientBAmount(
        uint112 poolToken,
        uint112 poolETH,
        uint112 liquidity,
        bool maxPermission
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Calculating amount of burnable liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolToken);
        vm.assume(liquidity * poolToken > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolETH);
        vm.assume(liquidity * poolETH > pairLiquidity + 1000);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(userA, poolToken);
        vm.deal(userA, poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(userA);
        vm.stopPrank();

        // Calculating amountETHMin to be one more than the amount of B that would be removed
        uint256 amountETHMin = (liquidity * poolETH) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) =
            generateUserAPermitSignature(pair, maxPermission ? type(uint256).max : liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        buttonwoodRouter.removeLiquidityETHWithPermit(
            address(tokenA), liquidity, 0, amountETHMin, userA, block.timestamp + 1, maxPermission, v, r, s
        );
    }

    function test_removeLiquidityETHWithPermit_maxPermissionAndSufficientAmounts(
        uint112 poolToken,
        uint112 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Calculating amount of liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolToken);
        vm.assume(liquidity * poolToken > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolETH);
        vm.assume(liquidity * poolETH > pairLiquidity + 1000);

        // Calculating amountToken and amountETH to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountToken = (liquidity * poolToken) / (pairLiquidity + 1000);
        uint256 expectedAmountETH = (liquidity * poolETH) / (pairLiquidity + 1000);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(userA, poolToken);
        vm.deal(userA, poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(userA);
        vm.stopPrank();

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        vm.prank(userA);
        (uint256 amountToken, uint256 amountETH) = buttonwoodRouter.removeLiquidityETHWithPermit(
            address(tokenA), liquidity, 0, 0, userA, block.timestamp + 1, true, v, r, s
        );

        // Ensuring amountToken and amountETH are as expected
        assertEq(amountToken, expectedAmountToken, "Did not remove expected amount of A");
        assertEq(amountETH, expectedAmountETH, "Did not remove expected amount of B");
    }

    function test_removeLiquidityETHWithPermit_specificPermissionAndSufficientAmounts(
        uint112 poolToken,
        uint112 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(poolToken > 10000);
        vm.assume(poolETH > 10000);

        // Calculating amount of liquidity in the pair
        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
        vm.assume(liquidity < pairLiquidity);

        // Ensuring liquidity burned doesn't cause overflow, nor remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity < type(uint112).max / poolToken);
        vm.assume(liquidity * poolToken > pairLiquidity + 1000);
        vm.assume(liquidity < type(uint112).max / poolETH);
        vm.assume(liquidity * poolETH > pairLiquidity + 1000);

        // Calculating amountToken and amountETH to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountToken = (liquidity * poolToken) / (pairLiquidity + 1000);
        uint256 expectedAmountETH = (liquidity * poolETH) / (pairLiquidity + 1000);

        // Having userA own the liquidity
        vm.startPrank(userA);
        // Creating the pair with poolToken:poolETH price ratio.
        tokenA.mint(userA, poolToken);
        vm.deal(userA, poolETH);
        weth.deposit{value: poolETH}();
        IButtonswapPair pair = IButtonswapPair(buttonswapFactory.createPair(address(tokenA), address(weth)));
        tokenA.transfer(address(pair), poolToken);
        weth.transfer(address(pair), poolETH);
        pair.mint(userA);
        vm.stopPrank();

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        vm.prank(userA);
        (uint256 amountToken, uint256 amountETH) = buttonwoodRouter.removeLiquidityETHWithPermit(
            address(tokenA), liquidity, 0, 0, userA, block.timestamp + 1, false, v, r, s
        );

        // Ensuring amountToken and amountETH are as expected
        assertEq(amountToken, expectedAmountToken, "Did not remove expected amount of A");
        assertEq(amountETH, expectedAmountETH, "Did not remove expected amount of B");
    }

    function test_swapExactTokensForTokens_insufficientOutputAmount(uint256 amountIn, uint256 amountOutMin, uint256[] calldata seedPoolOutAmounts) public {
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
            address pair = buttonswapFactory.createPair(path[idx], path[idx + 1]);
            MockRebasingERC20(path[idx]).mint(address(this), 10000);
            MockRebasingERC20(path[idx]).transfer(pair, 10000);
            MockRebasingERC20(path[idx + 1]).mint(address(this), poolOutAmounts[idx + 1]);
            MockRebasingERC20(path[idx + 1]).transfer(pair, poolOutAmounts[idx + 1]);
            IButtonswapPair(pair).mint(address(this));
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);

        // Ensuring that the output is always less than amountOutMin
        amountOutMin = bound(amountOutMin, amounts[amounts.length - 1] + 1, type(uint256).max);

        // Expecting to revert with `InsufficientOutputAmount()` error
        vm.expectRevert(IButtonwoodRouterErrors.InsufficientOutputAmount.selector);
        buttonwoodRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp + 1);
    }

    function test_swapExactTokensForTokens_sufficientOutputAmount(uint256 amountIn, uint256 amountOutMin, uint256[] calldata seedPoolOutAmounts) public {
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
            address pair = buttonswapFactory.createPair(path[idx], path[idx + 1]);
            MockRebasingERC20(path[idx]).mint(address(this), 10000);
            MockRebasingERC20(path[idx]).transfer(pair, 10000);
            MockRebasingERC20(path[idx + 1]).mint(address(this), poolOutAmounts[idx + 1]);
            MockRebasingERC20(path[idx + 1]).transfer(pair, poolOutAmounts[idx + 1]);
            IButtonswapPair(pair).mint(address(this));
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);

        // Ensuring that amountOutMin is always less than the final output
        amountOutMin = bound(amountOutMin, 0, amounts[amounts.length - 1]);

        // Minting the first token to be approved and swapped
        MockRebasingERC20(path[0]).mint(address(this), amountIn);
        MockRebasingERC20(path[0]).approve(address(buttonwoodRouter), amountIn);

        buttonwoodRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp + 1);

        // Asserting that the final token has the expected amount
        assertEq(MockRebasingERC20(path[path.length - 1]).balanceOf(address(this)), amounts[amounts.length - 1], "Did not receive expected amount of tokens");
    }
}
