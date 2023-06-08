// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapRouterErrors} from "../src/interfaces/IButtonswapRouter/IButtonswapRouterErrors.sol";
import {ButtonswapRouter} from "../src/ButtonswapRouter.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IButtonswapPairErrors} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPairErrors.sol";
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {MockWeth} from "./mocks/MockWeth.sol";
import {ButtonswapLibrary} from "../src/libraries/ButtonswapLibrary.sol";
import {Babylonian} from "../src/libraries/Babylonian.sol";
import {console} from "buttonswap-periphery_forge-std/Console.sol";
import {PairMath} from "buttonswap-periphery_buttonswap-core/libraries/PairMath.sol";

contract ButtonswapRouterTest is Test, IButtonswapRouterErrors {
    address public userA;
    uint256 public userAPrivateKey;
    //    address public userB = 0x000000000000000000000000000000000000000b;
    //    address public userC = 0x000000000000000000000000000000000000000C;
    //    address public userD = 0x000000000000000000000000000000000000000d;

    MockRebasingERC20 public tokenA;
    MockRebasingERC20 public tokenB;
    IWETH public weth;
    ButtonswapFactory public buttonswapFactory;

    ButtonswapRouter public buttonswapRouter;

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
                keccak256(abi.encode(pair.PERMIT_TYPEHASH(), userA, address(buttonswapRouter), liquidity, 0, deadline))
            )
        );
        return vm.sign(userAPrivateKey, permitDigest);
    }

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

    // Utility function for creating and initializing ETH-pairs with poolToken:poolETH price ratio. Does not use ButtonwoodRouter
    function createAndInitializePairETH(MockRebasingERC20 token, uint256 poolToken, uint256 poolETH)
        private
        returns (IButtonswapPair pair, uint256 liquidityOut)
    {
        pair = IButtonswapPair(buttonswapFactory.createPair(address(token), address(weth)));
        token.mint(address(this), poolToken);
        token.approve(address(pair), poolToken);
        vm.deal(address(this), poolETH);
        weth.deposit{value: poolETH}();
        weth.approve(address(pair), poolETH);

        if (pair.token0() == address(token)) {
            liquidityOut = pair.mint(poolToken, poolETH, address(this));
        } else {
            liquidityOut = pair.mint(poolETH, poolToken, address(this));
        }
    }

    // Required function for receiving ETH refunds
    receive() external payable {}

    function setUp() public {
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        tokenA = new MockRebasingERC20("TokenA", "TKNA", 18);
        tokenB = new MockRebasingERC20("TokenB", "TKNB", 18);
        weth = new MockWeth();
        buttonswapFactory = new ButtonswapFactory(userA);
        buttonswapRouter = new ButtonswapRouter(address(buttonswapFactory), address(weth));
    }

    function test_WETH() public {
        assertEq(buttonswapRouter.WETH(), address(weth));
    }

    function test_factory() public {
        assertEq(buttonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_constructor() public {
        assertEq(buttonswapRouter.WETH(), address(weth));
        assertEq(buttonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_receive_rejectNonWETHSender(uint256 ethAmount) public {
        // Sending ETH, ignoring data in return value
        (bool sent,) = payable(address(buttonswapRouter)).call{value: ethAmount}("");
        assertTrue(!sent, "Expected call to fail");
    }

    function test_receive_acceptWETHSender(uint256 ethAmount) public {
        vm.deal(address(weth), ethAmount);
        vm.prank(address(weth));
        // Sending ETH, ignoring data in return value
        (bool sent,) = payable(address(buttonswapRouter)).call{value: ethAmount}("");
        assertTrue(sent, "Expected call to succeed");
    }

    function test_addLiquidity_createsPairIfNoneExists(uint112 amountADesired, uint112 amountBDesired) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(amountADesired > 10000);
        vm.assume(amountBDesired > 10000);

        tokenA.mint(address(this), amountADesired);
        tokenB.mint(address(this), amountBDesired);
        tokenA.approve(address(buttonswapRouter), amountADesired);
        tokenB.approve(address(buttonswapRouter), amountBDesired);

        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Expect the factor to call createPair();
        vm.expectCall(
            address(buttonswapFactory), abi.encodeCall(ButtonswapFactory.createPair, (address(tokenA), address(tokenB)))
        );
        buttonswapRouter.addLiquidity(
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
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // The calculated amount of B needed to match `amountADesired` is less than `amountBDesired`
        // but also being less than `amountBMin` triggers the error
        vm.assume(amountADesired > 0);
        uint256 matchingBAmount = (uint256(amountADesired) * poolB) / poolA;
        vm.assume(matchingBAmount <= amountBDesired);
        vm.assume(matchingBAmount < amountBMin);

        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        buttonswapRouter.addLiquidity(
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
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

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
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        buttonswapRouter.addLiquidity(
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
        tokenA.approve(address(buttonswapRouter), amountADesired);
        tokenB.approve(address(buttonswapRouter), amountBDesired);

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
        tokenA.approve(address(buttonswapRouter), amountADesired);
        tokenB.approve(address(buttonswapRouter), amountBDesired);

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountA, uint256 amountB,) = buttonswapRouter.addLiquidity(
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
        tokenA.approve(address(buttonswapRouter), amountADesired);
        tokenB.approve(address(buttonswapRouter), amountBDesired);

        // Expect NoReservoir error to be thrown
        vm.expectRevert(IButtonswapRouterErrors.NoReservoir.selector);
        buttonswapRouter.addLiquidityWithReservoir(
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

        vm.expectRevert(IButtonswapRouterErrors.NotInitialized.selector);
        buttonswapRouter.addLiquidityWithReservoir(
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
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        vm.expectRevert(IButtonswapRouterErrors.NoReservoir.selector);
        buttonswapRouter.addLiquidityWithReservoir(
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

        // Creating the pair with poolA:poolB price ratio
        createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Rebasing tokenA 10% up to create a tokenA reservoir
        tokenA.applyMultiplier(11, 10);

        // Calculating a matching amount of tokenA to amountBDesired and ensuring it's under `amountAMin`
        uint256 matchingAAmount = (uint256(amountBDesired) * poolA) / poolB;
        uint256 amountAMin = matchingAAmount + 1;

        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        buttonswapRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), 0, amountBDesired, amountAMin, 0, userA, block.timestamp + 1
        );
    }

//    function test_addLiquidityWithReservoir_usingReservoirAWithInsufficientReservoir(uint112 poolA, uint112 poolB)
//        public
//    {
//        // Minting enough for minimum liquidity requirement
//        vm.assume(poolA > 10000);
//        vm.assume(poolB > 10000);
//
//        // Creating the pair with poolA:poolB price ratio
//        createAndInitializePair(tokenA, tokenB, poolA, poolB);
//
//        // Rebasing tokenA 10% up to create a tokenA reservoir
//        tokenA.applyMultiplier(11, 10);
//
//        // Calculating amountBDesired to be 2x more than the corresponding size of the reservoir
//        // TokenA rebased up 10%, so 10% of poolB matches the tokenA reservoir. 20% is poolB / 5.
//        uint256 amountBDesired = poolB / 5; // / 10 + 100000;
//
//        // ToDo: InsufficientAReservoir error is probably insufficient and will be removed
//        tokenB.mint(address(this), amountBDesired);
//        tokenB.approve(address(buttonswapRouter), amountBDesired);
//
//        vm.expectRevert(IButtonswapPairErrors.InsufficientReservoir.selector);
//        buttonswapRouter.addLiquidityWithReservoir(
//            address(tokenA), address(tokenB), 0, amountBDesired, 0, 0, userA, block.timestamp + 1
//        );
//    }

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
        tokenB.approve(address(buttonswapRouter), amountBDesired);

        buttonswapRouter.addLiquidityWithReservoir(
            address(tokenA), address(tokenB), 0, amountBDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    //    function test_addLiquidityWithReservoir_usingReservoirBWithInsufficientAmount(
    //        uint112 poolA,
    //        uint112 poolB,
    //        uint112 amountADesired
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolA > 10000);
    //        vm.assume(poolB > 10000);
    //
    //        // Making sure amountADesired is positive
    //        vm.assume(amountADesired > 0);
    //
    //        // Creating the pair with poolA:poolB price ratio
    //        createAndInitializePair(tokenA, tokenB, poolA, poolB);
    //
    //        // Rebasing tokenB 10% up to create a tokenA reservoir
    //        tokenB.applyMultiplier(11, 10);
    //
    //        // Calculating a matching amount of tokenB to amountADesired and ensuring it's under `amountBMin`
    //        uint256 matchingBAmount = (uint256(amountADesired) * poolB) / poolA;
    //        uint256 amountBMin = matchingBAmount + 1;
    //
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
    //        buttonswapRouter.addLiquidityWithReservoir(
    //            address(tokenA), address(tokenB), amountADesired, 0, 0, amountBMin, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_addLiquidityWithReservoir_usingReservoirBWithInsufficientReservoir(uint112 poolA, uint112 poolB)
    //        public
    //    {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolA > 10000);
    //        vm.assume(poolB > 10000);
    //
    //        // Creating the pair with poolA:poolB price ratio
    //        createAndInitializePair(tokenA, tokenB, poolA, poolB);
    //
    //        // Rebasing tokenB 10% up to create a tokenB reservoir
    //        tokenB.applyMultiplier(11, 10);
    //
    //        // Calculating amountADesired to be 2x more than the corresponding size of the reservoir
    //        // TokenB rebased up 10%, so 10% of poolA matches the tokenB reservoir. 20% is poolA / 5.
    //        uint256 amountADesired = poolA / 5; // / 10 + 100000;
    //
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientBReservoir.selector);
    //        buttonswapRouter.addLiquidityWithReservoir(
    //            address(tokenA), address(tokenB), amountADesired, 0, 0, 0, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_addLiquidityWithReservoir_usingReservoirBWithSufficientAmount(
    //        uint112 poolA,
    //        uint112 poolB,
    //        uint8 rebaseNumerator,
    //        uint8 rebaseDenominator,
    //        uint112 amountADesired
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolA > 10000);
    //        vm.assume(poolB > 10000);
    //
    //        // Ensuring it's a positive rebase that isn't too big
    //        vm.assume(rebaseDenominator > 0);
    //        vm.assume(rebaseNumerator > rebaseDenominator);
    //        vm.assume(poolB < (type(uint112).max / rebaseNumerator) * rebaseDenominator);
    //
    //        // Ensuring amountBDesired is between 0.01% and 100% of the reservoir, and that it doesn't cause overflow, and enough liquidity is minted
    //        uint256 reservoirBInTermsOfA = (uint256(poolA) * (rebaseNumerator - rebaseDenominator)) / rebaseDenominator;
    //        vm.assume(amountADesired > reservoirBInTermsOfA / 1000);
    //        vm.assume(amountADesired < reservoirBInTermsOfA);
    //        vm.assume(amountADesired < type(uint112).max / poolB);
    //        vm.assume(1000 * 2 * uint256(amountADesired) > 2 * uint256(poolA) + reservoirBInTermsOfA);
    //
    //        // Creating the pair with poolA:poolB price ratio
    //        createAndInitializePair(tokenA, tokenB, poolA, poolB);
    //
    //        // Rebasing tokenB positively up to create a tokenB reservoir
    //        tokenB.applyMultiplier(rebaseNumerator, rebaseDenominator);
    //
    //        // Giving approval for amountADesired tokenA
    //        tokenA.mint(address(this), amountADesired);
    //        tokenA.approve(address(buttonswapRouter), amountADesired);
    //
    //        buttonswapRouter.addLiquidityWithReservoir(
    //            address(tokenA), address(tokenB), amountADesired, 0, 0, 0, userA, block.timestamp + 1
    //        );
    //    }

    function test_addLiquidityETH_createsPairIfNoneExists(uint112 amountTokenDesired, uint112 amountETHSent) public {
        // Minting enough for minimum liquidity requirement
        vm.assume(amountTokenDesired > 10000);
        vm.assume(amountETHSent > 10000);

        tokenA.mint(address(this), amountTokenDesired);
        tokenA.approve(address(buttonswapRouter), amountTokenDesired);
        vm.deal(address(this), amountETHSent);

        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Expect the factor to call createPair();
        vm.expectCall(
            address(buttonswapFactory), abi.encodeCall(ButtonswapFactory.createPair, (address(tokenA), address(weth)))
        );
        buttonswapRouter.addLiquidityETH{value: amountETHSent}(
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
        createAndInitializePairETH(tokenA, poolToken, poolETH);

        // The calculated amount of ETH needed to match `amountTokenDesired` is less than `amountETHSent`
        // but also being less than `amountBMin` triggers the error
        vm.assume(amountTokenDesired > 0);
        uint256 matchingETHAmount = (uint256(amountTokenDesired) * poolETH) / poolToken;
        vm.assume(matchingETHAmount <= amountETHSent);
        vm.assume(matchingETHAmount < amountETHMin);

        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        buttonswapRouter.addLiquidityETH{value: amountETHSent}(
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
        createAndInitializePairETH(tokenA, poolToken, poolETH);

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
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        buttonswapRouter.addLiquidityETH{value: amountETHSent}(
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
        tokenA.approve(address(buttonswapRouter), amountTokenDesired);
        tokenB.approve(address(buttonswapRouter), amountETHSent);

        // Creating the pair with poolToken:poolETH price ratio
        createAndInitializePairETH(tokenA, poolToken, poolETH);

        // The matching amount of either token must fit within the bounds
        uint256 matchingTokenAmount = (uint256(amountETHSent) * poolToken) / poolETH;
        uint256 matchingETHAmount = (uint256(amountTokenDesired) * poolETH) / poolToken;
        vm.assume(
            (matchingTokenAmount <= amountTokenDesired && matchingTokenAmount > amountTokenMin)
                || (matchingETHAmount <= amountETHSent && matchingETHAmount > amountETHMin)
        );

        // Approving the router to take at most amountTokenDesired A tokens and at most amountETHSent B tokens
        tokenA.mint(address(this), amountTokenDesired);
        tokenA.approve(address(buttonswapRouter), amountTokenDesired);
        vm.deal(address(this), amountETHSent);

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountToken, uint256 amountETH,) = buttonswapRouter.addLiquidityETH{value: amountETHSent}(
            address(tokenA), amountTokenDesired, amountTokenMin, amountETHMin, userA, block.timestamp + 1
        );

        // Assert that deposited amounts are within bounds
        assert(amountToken > amountTokenMin && amountToken <= amountTokenDesired);
        assert(amountETH > amountETHMin && amountETH <= amountETHSent);

        // Asserting that remaining tokens are returned to the caller
        assertEq(tokenA.balanceOf(address(this)), amountTokenDesired - amountToken);
        assertEq(address(this).balance, amountETHSent - amountETH, "Test contract should be refunded the remaining ETH");
    }

    //    function test_addLiquidityETHWithReservoir_pairExistsButMissingReservoir(
    //        uint112 poolToken,
    //        uint112 poolETH,
    //        uint112 amountTokenDesired,
    //        uint112 amountETHSent
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //
    //        // Creating the pair with poolToken:poolETH price ratio. No rebase so no reservoir
    //        createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        vm.deal(address(this), amountETHSent);
    //        vm.expectRevert(IButtonswapRouterErrors.NoReservoir.selector);
    //        buttonswapRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
    //            address(tokenA), amountTokenDesired, 0, 0, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_addLiquidityETHWithReservoir_usingReservoirTokenWithInsufficientAmount(
    //        uint112 poolToken,
    //        uint112 poolETH,
    //        uint112 amountETHSent
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //
    //        // Making sure amountETHSent is positive
    //        vm.assume(amountETHSent > 0);
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        // Rebasing tokenA 10% up to create a tokenA reservoir
    //        tokenA.applyMultiplier(11, 10);
    //
    //        // Calculating a matching amount of tokenA to amountETHSent and ensuring it's under `amountTokenMin`
    //        uint256 matchingTokenAmount = (uint256(amountETHSent) * poolToken) / poolETH;
    //        uint256 amountTokenMin = matchingTokenAmount + 1;
    //
    //        vm.deal(address(this), amountETHSent);
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
    //        buttonswapRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
    //            address(tokenA), 0, amountTokenMin, 0, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_addLiquidityETHWithReservoir_usingReservoirTokenWithInsufficientReservoir(
    //        uint112 poolToken,
    //        uint112 poolETH
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        // Rebasing tokenA 10% up to create a tokenA reservoir
    //        tokenA.applyMultiplier(11, 10);
    //
    //        // Calculating amountETHSent to be 2x more than the corresponding size of the reservoir
    //        // TokenA rebased up 10%, so 10% of poolETH matches the tokenA reservoir. 20% is poolETH / 5.
    //        uint256 amountETHSent = poolETH / 5; // / 10 + 100000;
    //
    //        vm.deal(address(this), amountETHSent);
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientAReservoir.selector);
    //        buttonswapRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
    //            address(tokenA), 0, 0, 0, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_addLiquidityETHWithReservoir_usingReservoirTokenWithSufficientAmount(
    //        uint112 poolToken,
    //        uint112 poolETH,
    //        uint8 rebaseNumerator,
    //        uint8 rebaseDenominator,
    //        uint112 amountETHSent
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //
    //        // Ensuring it's a positive rebase that isn't too big
    //        vm.assume(rebaseDenominator > 0);
    //        vm.assume(rebaseNumerator > rebaseDenominator);
    //        vm.assume(poolToken < (type(uint112).max / rebaseNumerator) * rebaseDenominator);
    //
    //        // Ensuring amountETHSent is between 0.01% and 100% of the reservoir, and that it doesn't cause overflow, and enough liquidity is minted
    //        uint256 reservoirTokenInTermsOfETH =
    //            (uint256(poolETH) * (rebaseNumerator - rebaseDenominator)) / rebaseDenominator;
    //        vm.assume(amountETHSent > reservoirTokenInTermsOfETH / 10000);
    //        vm.assume(amountETHSent < reservoirTokenInTermsOfETH);
    //        vm.assume(amountETHSent < type(uint112).max / poolToken);
    //        vm.assume(10000 * amountETHSent > 2 * uint256(poolETH) + reservoirTokenInTermsOfETH);
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        // Rebasing tokenA positively up to create a tokenA reservoir
    //        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);
    //
    //        vm.deal(address(this), amountETHSent);
    //        buttonswapRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
    //            address(tokenA), 0, 0, 0, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_addLiquidityETHWithReservoir_usingReservoirETHWithInsufficientAmount(
    //        uint112 poolToken,
    //        uint112 poolETH,
    //        uint112 amountTokenDesired
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //
    //        // Making sure amountTokenDesired is positive
    //        vm.assume(amountTokenDesired > 0);
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        // Rebasing tokenA down 10% up to create an ETH reservoir (ETH can't rebase)
    //        tokenA.applyMultiplier(10, 11);
    //
    //        // Fetching new pool balances to avoid rounding errors in the test
    //        // When you rebase down, you lose precision, so we refetch pool balances. Rebasing up doesn't have this problem.
    //        (uint256 newPoolToken, uint256 newPoolETH) =
    //            ButtonswapLibrary.getPools(address(buttonswapFactory), address(tokenA), address(weth));
    //
    //        // Calculating a matching amount of ETH to amountTokenDesired and ensuring it's under `amountETHMin`
    //        uint256 matchingETHAmount = (amountTokenDesired * newPoolETH) / newPoolToken;
    //        uint256 amountETHMin = matchingETHAmount + 1;
    //
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
    //        buttonswapRouter.addLiquidityETHWithReservoir(
    //            address(tokenA), amountTokenDesired, 0, amountETHMin, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_addLiquidityETHWithReservoir_usingReservoirETHWithInsufficientReservoir(
    //        uint112 poolToken,
    //        uint112 poolETH
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        // Rebasing tokenA 10% down to create an ETH reservoir (ETH can't rebase)
    //        tokenA.applyMultiplier(10, 11);
    //
    //        // Calculating amountTokenDesired to be 2x more than the corresponding size of the reservoir
    //        // TokenB rebased up 10%, so 10% of poolToken matches the tokenB reservoir. 20% is poolToken / 5.
    //        uint256 amountTokenDesired = poolToken / 5; // / 10 + 100000;
    //
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientBReservoir.selector);
    //        buttonswapRouter.addLiquidityETHWithReservoir(
    //            address(tokenA), amountTokenDesired, 0, 0, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_addLiquidityETHWithReservoir_usingReservoirETHWithSufficientAmount(
    //        uint112 poolToken,
    //        uint112 poolETH,
    //        uint8 rebaseNumerator,
    //        uint8 rebaseDenominator,
    //        uint112 amountTokenDesired
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //
    //        // Ensuring it's a negative rebase that isn't too small (between 10% and 100%)
    //        rebaseDenominator = uint8(bound(rebaseDenominator, 100, type(uint8).max));
    //        rebaseNumerator = uint8(bound(rebaseNumerator, (uint256(rebaseDenominator) * 10) / 100, rebaseDenominator));
    //
    //        // Ensuring amountTokenDesired is between 0.01% and 100% of the reservoir, that it doesn't cause overflow, and enough liquidity is minted
    //        uint256 reservoirETHInTermsOfA =
    //            (uint256(poolToken) * (rebaseDenominator - rebaseNumerator)) / rebaseDenominator;
    //        vm.assume(amountTokenDesired > reservoirETHInTermsOfA / 1000);
    //        vm.assume(amountTokenDesired < reservoirETHInTermsOfA);
    //        vm.assume(amountTokenDesired < type(uint112).max / poolETH);
    //        vm.assume(
    //            10000 * uint256(amountTokenDesired)
    //                > 2 * uint256(poolToken) * rebaseNumerator / rebaseDenominator + reservoirETHInTermsOfA
    //        );
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        createAndInitializePairETH(tokenA, poolToken, poolETH);
    //        // Rebasing tokenA negatively down to create an ETH reservoir (ETH can't rebase)
    //        tokenA.applyMultiplier(rebaseNumerator, rebaseDenominator);
    //
    //        // Giving approval for amountTokenDesired tokenA
    //        tokenA.mint(address(this), amountTokenDesired);
    //        tokenA.approve(address(buttonswapRouter), amountTokenDesired);
    //
    //        buttonswapRouter.addLiquidityETHWithReservoir(
    //            address(tokenA), amountTokenDesired, 0, 0, userA, block.timestamp + 1
    //        );
    //    }

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

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = (liquidity * poolA) / (pairLiquidity + 1000) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonswapRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        buttonswapRouter.removeLiquidity(
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

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = (liquidity * poolB) / (pairLiquidity + 1000) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonswapRouter), liquidity);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        buttonswapRouter.removeLiquidity(
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

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonswapRouter), liquidity);

        (uint256 amountA, uint256 amountB) = buttonswapRouter.removeLiquidity(
            address(tokenA), address(tokenB), liquidity, amountAMin, amountBMin, userA, block.timestamp + 1
        );

        // Ensuring amountA and amountB are as expected
        assertEq(amountA, expectedAmountA, "Did not remove expected amount of A");
        assertEq(amountB, expectedAmountB, "Did not remove expected amount of B");
    }

    //    function test_removeLiquidityFromReservoir_insufficientAAmount(uint112 poolA, uint112 poolB, uint112 liquidity)
    //        public
    //    {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolA > 10000);
    //        vm.assume(poolB > 10000);
    //
    //        // Calculating amount of burnable liquidity in the pair
    //        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
    //        vm.assume(liquidity < pairLiquidity);
    //
    //        // Calculating expected amount of tokenA to be removed, and ensuring it doesn't cause errors
    //        uint256 expectedAmountA = (liquidity * (uint256(poolA) * 21 / 10)) / (pairLiquidity + 1000);
    //        vm.assume(expectedAmountA > 0);
    //        vm.assume(expectedAmountA < poolA / 10); // reservoirA = 10% of poolA
    //
    //        // Creating the pair with poolA:poolB price ratio
    //        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
    //
    //        // Rebasing tokenA up 10% and creating the tokenA reservoir
    //        tokenA.applyMultiplier(11, 10);
    //
    //        // Calculating amountAMin to be one more than the amount of A that would be removed
    //        uint256 amountAMin = expectedAmountA + 1;
    //
    //        // Giving permission to the pair to burn liquidity
    //        pair.approve(address(buttonswapRouter), liquidity);
    //
    //        // Expecting to revert with `InsufficientAAmount()` error
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
    //        buttonswapRouter.removeLiquidityFromReservoir(
    //            address(tokenA), address(tokenB), liquidity, amountAMin, 0, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_removeLiquidityFromReservoir_insufficientBAmount(uint112 poolA, uint112 poolB, uint112 liquidity)
    //        public
    //    {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolA > 10000);
    //        vm.assume(poolB > 10000);
    //
    //        // Calculating amount of burnable liquidity in the pair
    //        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
    //        vm.assume(liquidity < pairLiquidity);
    //
    //        // Calculating expected amount of tokenB to be removed, and ensuring it doesn't cause errors
    //        uint256 expectedAmountB = (liquidity * (uint256(poolB) * 21 / 10)) / (pairLiquidity + 1000);
    //        vm.assume(expectedAmountB > 0);
    //        vm.assume(expectedAmountB < poolB / 10); // reservoirB = 10% of poolB
    //
    //        // Creating the pair with poolA:poolB price ratio
    //        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
    //
    //        // Rebasing tokenB up 10% and creating the tokenA reservoir
    //        tokenB.applyMultiplier(11, 10);
    //
    //        // Calculating amountBMin to be one more than the amount of B that would be removed
    //        uint256 amountBMin = expectedAmountB + 1;
    //
    //        // Giving permission to the pair to burn liquidity
    //        pair.approve(address(buttonswapRouter), liquidity);
    //
    //        // Expecting to revert with `InsufficientBAmount()` error
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
    //        buttonswapRouter.removeLiquidityFromReservoir(
    //            address(tokenA), address(tokenB), liquidity, 0, amountBMin, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_removeLiquidityFromReservoir_usingReservoirAWithSufficientAmount(
    //        uint112 poolA,
    //        uint112 poolB,
    //        uint112 liquidity,
    //        uint256 positiveRebasePercentage
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolA > 10000);
    //        vm.assume(poolB > 10000);
    //        positiveRebasePercentage = bound(positiveRebasePercentage, 1, 100);
    //
    //        // Calculating amount of burnable liquidity in the pair
    //        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
    //        vm.assume(liquidity < pairLiquidity);
    //
    //        // Calculating expected amount of tokenA to be removed, and ensuring it doesn't cause errors
    //        uint256 expectedAmountA =
    //            (liquidity * (uint256(poolA) * (200 + positiveRebasePercentage) / 100)) / (pairLiquidity + 1000);
    //        vm.assume(expectedAmountA > 0);
    //        vm.assume(expectedAmountA < (poolA * positiveRebasePercentage) / 100);
    //
    //        // Creating the pair with poolA:poolB price ratio
    //        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
    //
    //        // Rebasing tokenA up `positiveRebasePercentage`% and creating the tokenA reservoir
    //        tokenA.applyMultiplier(100 + positiveRebasePercentage, 100);
    //
    //        // Giving permission to the pair to burn liquidity
    //        pair.approve(address(buttonswapRouter), liquidity);
    //
    //        // Removing liquidity from the reservoir
    //        (uint256 amountA, uint256 amountB) = buttonswapRouter.removeLiquidityFromReservoir(
    //            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1
    //        );
    //
    //        // Checking that the correct amount of tokenA was removed and no tokenB was removed
    //        assertEq(amountA, expectedAmountA, "Incorrect amount of tokenA removed");
    //        assertEq(amountB, 0, "Incorrect amount of tokenB removed");
    //    }
    //
    //    function test_removeLiquidityFromReservoir_usingReservoirBWithSufficientAmount(
    //        uint112 poolA,
    //        uint112 poolB,
    //        uint112 liquidity,
    //        uint256 positiveRebasePercentage
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolA > 10000);
    //        vm.assume(poolB > 10000);
    //        positiveRebasePercentage = bound(positiveRebasePercentage, 1, 100);
    //
    //        // Calculating amount of burnable liquidity in the pair
    //        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolA) * poolB) - 1000;
    //        vm.assume(liquidity < pairLiquidity);
    //
    //        // Calculating expected amount of tokenB to be removed, and ensuring it doesn't cause errors
    //        uint256 expectedAmountB =
    //            (liquidity * (uint256(poolB) * (200 + positiveRebasePercentage) / 100)) / (pairLiquidity + 1000);
    //        vm.assume(expectedAmountB > 0);
    //        vm.assume(expectedAmountB < (poolB * positiveRebasePercentage) / 100);
    //
    //        // Creating the pair with poolA:poolB price ratio
    //        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
    //
    //        // Rebasing tokenB up `positiveRebasePercentage`% and creating the tokenB reservoir
    //        tokenB.applyMultiplier(100 + positiveRebasePercentage, 100);
    //
    //        // Giving permission to the pair to burn liquidity
    //        pair.approve(address(buttonswapRouter), liquidity);
    //
    //        // Removing liquidity from the reservoir
    //        (uint256 amountA, uint256 amountB) = buttonswapRouter.removeLiquidityFromReservoir(
    //            address(tokenA), address(tokenB), liquidity, 0, 0, userA, block.timestamp + 1
    //        );
    //
    //        // Checking that the correct amount of tokenB was removed and no tokenA was removed
    //        assertEq(amountA, 0, "Incorrect amount of tokenA removed");
    //        assertEq(amountB, expectedAmountB, "Incorrect amount of tokenB removed");
    //    }

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
        (IButtonswapPair pair,) = createAndInitializePairETH(tokenA, poolToken, poolETH);

        // Calculating amountTokenMin to be one more than the amount of A that would be removed
        uint256 amountTokenMin = (liquidity * poolToken) / (pairLiquidity + 1000) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonswapRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        buttonswapRouter.removeLiquidityETH(address(tokenA), liquidity, amountTokenMin, 0, userA, block.timestamp + 1);
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

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(tokenA, poolToken, poolETH);

        // Calculating amountETHMin to be one more than the amount of B that would be removed
        uint256 amountETHMin = (liquidity * poolETH) / (pairLiquidity + 1000) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonswapRouter), liquidity);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        buttonswapRouter.removeLiquidityETH(address(tokenA), liquidity, 0, amountETHMin, userA, block.timestamp + 1);
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

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(tokenA, poolToken, poolETH);

        // Giving permission to the pair to burn liquidity
        pair.approve(address(buttonswapRouter), liquidity);

        (uint256 amountToken, uint256 amountETH) = buttonswapRouter.removeLiquidityETH(
            address(tokenA), liquidity, amountTokenMin, amountETHMin, userA, block.timestamp + 1
        );

        // Ensuring amountToken and amountETH are as expected
        assertEq(amountToken, expectedAmountToken, "Did not remove expected amount of A");
        assertEq(amountETH, expectedAmountETH, "Did not remove expected amount of B");
    }

    //    function test_removeLiquidityETHFromReservoir_insufficientAAmount(
    //        uint112 poolToken,
    //        uint112 poolETH,
    //        uint112 liquidity
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //
    //        // Calculating amount of burnable liquidity in the pair
    //        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
    //        vm.assume(liquidity < pairLiquidity);
    //
    //        // Calculating expected amount of tokenA to be removed, and ensuring it doesn't cause errors
    //        uint256 expectedAmountToken = (liquidity * (uint256(poolToken) * 21 / 10)) / (pairLiquidity + 1000);
    //        vm.assume(expectedAmountToken > 0);
    //        vm.assume(expectedAmountToken < poolToken / 10); // reservoirA = 10% of poolToken
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        (IButtonswapPair pair,) = createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        // Rebasing tokenA up 10% and creating the tokenA reservoir
    //        tokenA.applyMultiplier(11, 10);
    //
    //        // Calculating amountTokenMin to be one more than the amount of A that would be removed
    //        uint256 amountTokenMin = expectedAmountToken + 1;
    //
    //        // Giving permission to the pair to burn liquidity
    //        pair.approve(address(buttonswapRouter), liquidity);
    //
    //        // Expecting to revert with `InsufficientAAmount()` error
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
    //        buttonswapRouter.removeLiquidityETHFromReservoir(
    //            address(tokenA), liquidity, amountTokenMin, 0, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_removeLiquidityETHFromReservoir_insufficientBAmount(
    //        uint112 poolToken,
    //        uint112 poolETH,
    //        uint112 liquidity
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //
    //        // Calculating amount of burnable liquidity in the pair
    //        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
    //        vm.assume(liquidity < pairLiquidity);
    //
    //        // Calculating expected amount of tokenB to be removed, and ensuring it doesn't cause errors
    //        uint256 newPoolToken = (uint256(poolToken) * (100 - 10)) / 100;
    //        uint256 newPoolETH = newPoolToken * poolETH / poolToken;
    //        uint256 newReservoirETH = poolETH - newPoolETH;
    //        uint256 expectedAmountETH = (liquidity * (newReservoirETH + newPoolETH + newPoolETH)) / (pairLiquidity + 1000);
    //        vm.assume(expectedAmountETH > 0);
    //        vm.assume(expectedAmountETH < poolETH / 10); // reservoirB = 10% of poolETH
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        (IButtonswapPair pair,) = createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        // Rebasing tokenA 10% down to create an ETH reservoir (ETH can't rebase)
    //        tokenA.applyMultiplier(9, 10);
    //
    //        // Calculating amountETHMin to be two more than the amount of A that would be removed
    //        // +2 instead of +1 because rebasing down causes additional rounding errors the math
    //        uint256 amountETHMin = expectedAmountETH + 2;
    //
    //        // Giving permission to the pair to burn liquidity
    //        pair.approve(address(buttonswapRouter), liquidity);
    //
    //        // Expecting to revert with `InsufficientBAmount()` error
    //        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
    //        buttonswapRouter.removeLiquidityETHFromReservoir(
    //            address(tokenA), liquidity, 0, amountETHMin, userA, block.timestamp + 1
    //        );
    //    }
    //
    //    function test_removeLiquidityETHFromReservoir_usingReservoirAWithSufficientAmount(
    //        uint112 poolToken,
    //        uint112 poolETH,
    //        uint112 liquidity,
    //        uint256 positiveRebasePercentage
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //        positiveRebasePercentage = bound(positiveRebasePercentage, 1, 100);
    //
    //        // Calculating amount of burnable liquidity in the pair
    //        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
    //        vm.assume(liquidity < pairLiquidity);
    //
    //        // Calculating expected amount of tokenA to be removed, and ensuring it doesn't cause errors
    //        uint256 expectedAmountToken =
    //            (liquidity * (uint256(poolToken) * (200 + positiveRebasePercentage) / 100)) / (pairLiquidity + 1000);
    //        vm.assume(expectedAmountToken > 0);
    //        vm.assume(expectedAmountToken < (poolToken * positiveRebasePercentage) / 100);
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        (IButtonswapPair pair,) = createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        // Rebasing tokenA up `positiveRebasePercentage`% and creating the tokenA reservoir
    //        tokenA.applyMultiplier(100 + positiveRebasePercentage, 100);
    //
    //        // Giving permission to the pair to burn liquidity
    //        pair.approve(address(buttonswapRouter), liquidity);
    //
    //        // Removing liquidity from the reservoir
    //        (uint256 amountToken, uint256 amountETH) = buttonswapRouter.removeLiquidityETHFromReservoir(
    //            address(tokenA), liquidity, 0, 0, userA, block.timestamp + 1
    //        );
    //
    //        // Checking that the correct amount of tokenA was removed and no ETH was removed
    //        assertEq(amountToken, expectedAmountToken, "Incorrect amount of tokenA removed");
    //        assertEq(amountETH, 0, "Incorrect amount of ETH removed");
    //    }
    //
    //    function test_removeLiquidityETHFromReservoir_usingReservoirBWithSufficientAmount(
    //        uint112 poolToken,
    //        uint112 poolETH,
    //        uint112 liquidity,
    //        uint256 negativeRebasePercentage
    //    ) public {
    //        // Minting enough for minimum liquidity requirement
    //        vm.assume(poolToken > 10000);
    //        vm.assume(poolETH > 10000);
    //        negativeRebasePercentage = bound(negativeRebasePercentage, 1, 99);
    //
    //        // Calculating amount of burnable liquidity in the pair
    //        uint256 pairLiquidity = Babylonian.sqrt(uint256(poolToken) * poolETH) - 1000;
    //        vm.assume(liquidity < pairLiquidity);
    //
    //        // Calculating expected amount of ETH to be removed, and ensuring it doesn't cause errors
    //        uint256 newPoolToken = (poolToken * (100 - negativeRebasePercentage)) / 100;
    //        uint256 newPoolETH = newPoolToken * poolETH / poolToken;
    //        uint256 newReservoirETH = poolETH - newPoolETH;
    //        uint256 expectedAmountETH = (liquidity * (newReservoirETH + newPoolETH + newPoolETH)) / (pairLiquidity + 1000);
    //
    //        vm.assume(expectedAmountETH > 0);
    //        vm.assume(expectedAmountETH < (poolETH * negativeRebasePercentage) / 100);
    //
    //        // Creating the pair with poolToken:poolETH price ratio
    //        (IButtonswapPair pair,) = createAndInitializePairETH(tokenA, poolToken, poolETH);
    //
    //        // Rebasing tokenA down `negativeRebasePercentage`% and creating the ETH reservoir (ETH can't rebase)
    //        tokenA.applyMultiplier(100 - negativeRebasePercentage, 100);
    //
    //        // Giving permission to the pair to burn liquidity
    //        pair.approve(address(buttonswapRouter), liquidity);
    //
    //        // Removing liquidity from the reservoir
    //        (uint256 amountToken, uint256 amountETH) = buttonswapRouter.removeLiquidityETHFromReservoir(
    //            address(tokenA), liquidity, 0, 0, userA, block.timestamp + 1
    //        );
    //
    //        // Checking that the correct amount of ETH was removed and no token A was removed
    //        assertEq(amountToken, 0, "Incorrect amount of tokenA removed");
    //        assertApproxEqAbs(amountETH, expectedAmountETH, 1);
    //    }

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

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = (liquidity * poolA) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        buttonswapRouter.removeLiquidityWithPermit(
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

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Calculating amountAMin to be one more than the amount of A that would be removed
        uint256 amountAMin = (liquidity * poolA) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        buttonswapRouter.removeLiquidityWithPermit(
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

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = (liquidity * poolB) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        buttonswapRouter.removeLiquidityWithPermit(
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

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Calculating amountBMin to be one more than the amount of B that would be removed
        uint256 amountBMin = (liquidity * poolB) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        buttonswapRouter.removeLiquidityWithPermit(
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

        // Creating the pair with poolA:poolB price ratio
        (IButtonswapPair pair,) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, liquidity);

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        vm.prank(userA);
        (uint256 amountA, uint256 amountB) = buttonswapRouter.removeLiquidityWithPermit(
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

        // Creating the pair with poolA:poolB price ratio
        IButtonswapPair pair;
        // Reusing pairLiquidity to store the amount of liquidityOut (to avoid ir-compilation)
        (pair, pairLiquidity) = createAndInitializePair(tokenA, tokenB, poolA, poolB);
        // Having userA own the liquidity
        pair.transfer(userA, pairLiquidity);

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        vm.prank(userA);
        (uint256 amountA, uint256 amountB) = buttonswapRouter.removeLiquidityWithPermit(
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

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenA, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Calculating amountTokenMin to be one more than the amount of A that would be removed
        uint256 amountTokenMin = (liquidity * poolToken) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) =
            generateUserAPermitSignature(pair, maxPermission ? type(uint256).max : liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        buttonswapRouter.removeLiquidityETHWithPermit(
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

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenA, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Calculating amountETHMin to be one more than the amount of B that would be removed
        uint256 amountETHMin = (liquidity * poolETH) / (pairLiquidity + 1000) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) =
            generateUserAPermitSignature(pair, maxPermission ? type(uint256).max : liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        buttonswapRouter.removeLiquidityETHWithPermit(
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

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenA, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        vm.prank(userA);
        (uint256 amountToken, uint256 amountETH) = buttonswapRouter.removeLiquidityETHWithPermit(
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

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(tokenA, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        vm.prank(userA);
        (uint256 amountToken, uint256 amountETH) = buttonswapRouter.removeLiquidityETHWithPermit(
            address(tokenA), liquidity, 0, 0, userA, block.timestamp + 1, false, v, r, s
        );

        // Ensuring amountToken and amountETH are as expected
        assertEq(amountToken, expectedAmountToken, "Did not remove expected amount of A");
        assertEq(amountETH, expectedAmountETH, "Did not remove expected amount of B");
    }

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
        buttonswapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp + 1);
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
        MockRebasingERC20(path[0]).approve(address(buttonswapRouter), amountIn);

        (uint256[] memory amounts) =
            buttonswapRouter.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp + 1);

        // Checking that the amounts in the trade are as expected
        assertEq(amounts, expectedAmounts, "Amounts in the trade are not as expected");

        // Checking that callee received the expected amount of the final token
        assertEq(
            MockRebasingERC20(path[path.length - 1]).balanceOf(address(this)),
            amounts[amounts.length - 1],
            "Did not receive expected amount of tokens"
        );
    }

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
        buttonswapRouter.swapTokensForExactTokens(amountOut, amountInMax, path, address(this), block.timestamp + 1);
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
        MockRebasingERC20(path[0]).approve(address(buttonswapRouter), amountInMax);

        (uint256[] memory amounts) =
            buttonswapRouter.swapTokensForExactTokens(amountOut, amountInMax, path, address(this), block.timestamp + 1);

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

    function test_swapExactETHForTokens_firstTokenIsNonWeth(
        uint256 amountETHSent,
        uint256 amountOutMin,
        uint256[] calldata seedPoolOutAmounts
    ) public {
        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountETHSent = bound(amountETHSent, 1000, 10000);

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
        // Key thing here is that the first token is not WETH
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

        // Expecting to revert with `InvalidPath()` error
        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonswapRouterErrors.InvalidPath.selector);
        buttonswapRouter.swapExactETHForTokens{value: amountETHSent}(
            amountOutMin, path, address(this), block.timestamp + 1
        );
    }

    function test_swapExactETHForTokens_insufficientOutputAmount(
        uint256 amountETHSent,
        uint256 amountOutMin,
        uint256[] calldata seedPoolOutAmounts
    ) public {
        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountETHSent = bound(amountETHSent, 1000, 10000);

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
        path[0] = address(weth);
        for (uint256 idx = 1; idx < path.length; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }

        // Create the pairs and populating the pools
        for (uint256 idx; idx < path.length - 1; idx++) {
            if (idx == 0) {
                createAndInitializePairETH(MockRebasingERC20(path[idx + 1]), 10000, poolOutAmounts[idx + 1]);
            } else {
                createAndInitializePair(
                    MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx + 1]), 10000, poolOutAmounts[idx]
                );
            }
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountETHSent, path);

        // Ensuring that the output is always less than amountOutMin
        amountOutMin = bound(amountOutMin, amounts[amounts.length - 1] + 1, type(uint256).max);

        // Expecting to revert with `InsufficientOutputAmount()` error
        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonswapRouterErrors.InsufficientOutputAmount.selector);
        buttonswapRouter.swapExactETHForTokens{value: amountETHSent}(
            amountOutMin, path, address(this), block.timestamp + 1
        );
    }

    function test_swapExactETHForTokens_sufficientOutputAmount(
        uint256 amountETHSent,
        uint256 amountOutMin,
        uint256[] calldata seedPoolOutAmounts
    ) public {
        // Ensuring that amountIn is bounded to avoid errors/overflows/underflows
        amountETHSent = bound(amountETHSent, 1000, 10000);

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
        path[0] = address(weth);
        for (uint256 idx = 1; idx < path.length; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }

        // Create the pairs and populating the pools
        for (uint256 idx; idx < path.length - 1; idx++) {
            if (idx == 0) {
                createAndInitializePairETH(MockRebasingERC20(path[idx + 1]), 10000, poolOutAmounts[idx + 1]);
            } else {
                createAndInitializePair(
                    MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx + 1]), 10000, poolOutAmounts[idx]
                );
            }
        }

        uint256[] memory expectedAmounts =
            ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountETHSent, path);

        // Ensuring that amountOutMin is always less than the final output
        amountOutMin = bound(amountOutMin, 0, expectedAmounts[expectedAmounts.length - 1]);

        // Performing the swaps with the ETH
        vm.deal(address(this), amountETHSent);
        (uint256[] memory amounts) = buttonswapRouter.swapExactETHForTokens{value: amountETHSent}(
            amountOutMin, path, address(this), block.timestamp + 1
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

    function test_swapTokensForExactETH_lastTokenIsNonWeth(
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

        // Creating all the tokens for the path (last token is not WETH)
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

        // Expecting to revert with `InvalidPath()` error
        vm.expectRevert(IButtonswapRouterErrors.InvalidPath.selector);
        buttonswapRouter.swapTokensForExactETH(amountOut, amountInMax, path, address(this), block.timestamp + 1);
    }

    function test_swapTokensForExactETH_excessiveInputAmount(
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

        // Creating all the tokens for the path (last token is WETH)
        address[] memory path = new address[](poolOutAmounts.length);
        for (uint256 idx; idx < path.length - 1; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }
        path[path.length - 1] = address(weth);

        // Create the pairs and calculate expected amounts
        for (uint256 idx = path.length - 1; idx > 0; idx--) {
            if (idx == path.length - 1) {
                createAndInitializePairETH(MockRebasingERC20(path[idx - 1]), 10000, poolOutAmounts[idx]);
            } else {
                createAndInitializePair(
                    MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx - 1]), poolOutAmounts[idx], 10000
                );
            }
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);

        // Ensuring that the input is always greater than amountInMax
        amountInMax = bound(amountInMax, 0, amounts[0] - 1);

        // Expecting to revert with `ExcessiveInputAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.ExcessiveInputAmount.selector);
        buttonswapRouter.swapTokensForExactETH(amountOut, amountInMax, path, address(this), block.timestamp + 1);
    }

    function test_swapTokensForExactETH_nonExcessiveInputAmount(
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

        // Creating all the tokens for the path (last token is WETH)
        address[] memory path = new address[](poolOutAmounts.length);
        for (uint256 idx; idx < path.length - 1; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }
        path[path.length - 1] = address(weth);

        // Create the pairs and calculate expected amounts
        for (uint256 idx = path.length - 1; idx > 0; idx--) {
            if (idx == path.length - 1) {
                createAndInitializePairETH(MockRebasingERC20(path[idx - 1]), 10000, poolOutAmounts[idx]);
            } else {
                createAndInitializePair(
                    MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx - 1]), poolOutAmounts[idx], 10000
                );
            }
        }

        uint256[] memory expectedAmounts = ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);

        // Ensuring that the amountInMax is always greater than the input (but also don't want to trigger minting error)
        amountInMax = bound(amountInMax, expectedAmounts[0], type(uint112).max);

        // Minting the first token to be approved and swapped (with the amountInMax)
        MockRebasingERC20(path[0]).mint(address(this), amountInMax);
        MockRebasingERC20(path[0]).approve(address(buttonswapRouter), amountInMax);

        (uint256[] memory amounts) =
            buttonswapRouter.swapTokensForExactETH(amountOut, amountInMax, path, address(this), block.timestamp + 1);

        // Checking that the amounts in the trade are as expected
        assertEq(amounts, expectedAmounts, "Amounts in the trade are not as expected");

        // Checking that correct amount of the first token was sent
        assertEq(
            MockRebasingERC20(path[0]).balanceOf(address(this)),
            amountInMax - expectedAmounts[0],
            "Sent more tokens than expected"
        );

        // Checking that correct amount of ETH was received
        assertEq(address(this).balance, amountOut, "Received more ETH than expected");
    }

    function test_swapExactTokensForETH_lastTokenIsNonWeth(
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

        // Creating all the tokens for the path (last token is not WETH)
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

        // Expecting to revert with `InvalidPath()` error
        vm.expectRevert(IButtonswapRouterErrors.InvalidPath.selector);
        buttonswapRouter.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), block.timestamp + 1);
    }

    function test_swapExactTokensForETH_insufficientOutputAmount(
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

        // Creating all the tokens for the path (last token is WETH)
        address[] memory path = new address[](poolOutAmounts.length);
        for (uint256 idx; idx < path.length - 1; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }
        path[path.length - 1] = address(weth);

        // Create the pairs and populating the pools
        for (uint256 idx; idx < path.length - 1; idx++) {
            if (idx == path.length - 2) {
                createAndInitializePairETH(MockRebasingERC20(path[idx]), 10000, poolOutAmounts[idx + 1]);
            } else {
                createAndInitializePair(
                    MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx + 1]), 10000, poolOutAmounts[idx + 1]
                );
            }
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);

        // Ensuring that the output is always less than amountOutMin
        amountOutMin = bound(amountOutMin, amounts[amounts.length - 1] + 1, type(uint256).max);

        // Expecting to revert with `InsufficientOutputAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientOutputAmount.selector);
        buttonswapRouter.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), block.timestamp + 1);
    }

    function test_swapExactTokensForETH_sufficientOutputAmount(
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

        // Creating all the tokens for the path (last token is WETH)
        address[] memory path = new address[](poolOutAmounts.length);
        for (uint256 idx; idx < path.length - 1; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }
        path[path.length - 1] = address(weth);

        // Create the pairs and populating the pools
        for (uint256 idx; idx < path.length - 1; idx++) {
            if (idx == path.length - 2) {
                createAndInitializePairETH(MockRebasingERC20(path[idx]), 10000, poolOutAmounts[idx + 1]);
            } else {
                createAndInitializePair(
                    MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx + 1]), 10000, poolOutAmounts[idx + 1]
                );
            }
        }

        uint256[] memory expectedAmounts = ButtonswapLibrary.getAmountsOut(address(buttonswapFactory), amountIn, path);

        // Ensuring that amountOutMin is always less than the final output
        amountOutMin = bound(amountOutMin, 0, expectedAmounts[expectedAmounts.length - 1]);

        // Minting the first token to be approved and swapped
        MockRebasingERC20(path[0]).mint(address(this), amountIn);
        MockRebasingERC20(path[0]).approve(address(buttonswapRouter), amountIn);

        (uint256[] memory amounts) =
            buttonswapRouter.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), block.timestamp + 1);

        // Checking that the amounts in the trade are as expected
        assertEq(amounts, expectedAmounts, "Amounts in the trade are not as expected");

        // Checking that callee received the expected amount of the final token
        assertEq(address(this).balance, amounts[amounts.length - 1], "Did not receive expected amount of ETH");
    }

    function test_swapETHForExactTokens_firstTokenIsNonWeth(
        uint256 amountOut,
        uint256 amountETHSent,
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

        // Creating all the tokens for the path (first token is not WETH)
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

        // Expecting to revert with `InvalidPath()` error
        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonswapRouterErrors.InvalidPath.selector);
        buttonswapRouter.swapETHForExactTokens(amountOut, path, address(this), block.timestamp + 1);
    }

    function test_swapETHForExactTokens_excessiveInputAmount(
        uint256 amountOut,
        uint256 amountETHSent,
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

        // Creating all the tokens for the path (first token is WETH)
        address[] memory path = new address[](poolOutAmounts.length);
        path[0] = address(weth);
        for (uint256 idx = 1; idx < path.length; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }

        // Create the pairs and calculate expected amounts
        for (uint256 idx = path.length - 1; idx > 0; idx--) {
            if (idx == 1) {
                createAndInitializePairETH(MockRebasingERC20(path[idx]), poolOutAmounts[idx], 10000);
            } else {
                createAndInitializePair(
                    MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx - 1]), poolOutAmounts[idx], 10000
                );
            }
        }

        uint256[] memory amounts = ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);

        // Ensuring that the input is always greater than amountETHSent (not sending enough ETH)
        amountETHSent = bound(amountETHSent, 0, amounts[0] - 1);

        // Expecting to revert with `ExcessiveInputAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.ExcessiveInputAmount.selector);
        buttonswapRouter.swapETHForExactTokens(amountOut, path, address(this), block.timestamp + 1);
    }

    function test_swapETHForExactTokens_nonExcessiveInputAmount(
        uint256 amountOut,
        uint256 amountETHSent,
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

        // Creating all the tokens for the path (first token is WETH)
        address[] memory path = new address[](poolOutAmounts.length);
        path[0] = address(weth);
        for (uint256 idx = 1; idx < path.length; idx++) {
            MockRebasingERC20 token = new MockRebasingERC20("Token", "TKN", 18);
            path[idx] = address(token);
        }

        // Create the pairs and calculate expected amounts
        for (uint256 idx = path.length - 1; idx > 0; idx--) {
            if (idx == 1) {
                createAndInitializePairETH(MockRebasingERC20(path[idx]), poolOutAmounts[idx], 10000);
            } else {
                createAndInitializePair(
                    MockRebasingERC20(path[idx]), MockRebasingERC20(path[idx - 1]), poolOutAmounts[idx], 10000
                );
            }
        }

        uint256[] memory expectedAmounts = ButtonswapLibrary.getAmountsIn(address(buttonswapFactory), amountOut, path);

        // Ensuring that the amountETHSent is always greater than the input (but also don't want to trigger minting error)
        amountETHSent = bound(amountETHSent, expectedAmounts[0], type(uint112).max);

        vm.deal(address(this), amountETHSent);
        (uint256[] memory amounts) = buttonswapRouter.swapETHForExactTokens{value: amountETHSent}(
            amountOut, path, address(this), block.timestamp + 1
        );

        // Checking that the amounts in the trade are as expected
        assertEq(amounts, expectedAmounts, "Amounts in the trade are not as expected");

        // Checking that correct amount of the first token was sent
        assertEq(address(this).balance, amountETHSent - expectedAmounts[0], "Sent more tokens than expected");

        // Checking that correct amount of the last token was received
        assertEq(
            MockRebasingERC20(path[path.length - 1]).balanceOf(address(this)),
            amountOut,
            "Received less tokens than expected"
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
