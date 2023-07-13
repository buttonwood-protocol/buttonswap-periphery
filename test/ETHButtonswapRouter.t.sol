// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {IButtonswapRouterErrors} from "../src/interfaces/IButtonswapRouter/IButtonswapRouterErrors.sol";
import {IETHButtonswapRouterErrors} from "../src/interfaces/IButtonswapRouter/IETHButtonswapRouterErrors.sol";
import {ETHButtonswapRouter} from "../src/ETHButtonswapRouter.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {MockWeth} from "./mocks/MockWeth.sol";
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {ButtonswapLibrary} from "../src/libraries/ButtonswapLibrary.sol";
import {PairMath} from "buttonswap-periphery_buttonswap-core/libraries/PairMath.sol";

contract ETHButtonswapRouterTest is Test, IButtonswapRouterErrors, IETHButtonswapRouterErrors {
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
    MockRebasingERC20 public rebasingToken;
    IWETH public weth;
    ButtonswapFactory public buttonswapFactory;
    ETHButtonswapRouter public ethButtonswapRouter;

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
                    abi.encode(pair.PERMIT_TYPEHASH(), userA, address(ethButtonswapRouter), liquidity, 0, deadline)
                )
            )
        );
        return vm.sign(userAPrivateKey, permitDigest);
    }

    // Required function for receiving ETH refunds
    receive() external payable {}

    function setUp() public {
        (feeToSetter, feeToSetterPrivateKey) = makeAddrAndKey("feeToSetter");
        (isCreationRestrictedSetter, isCreationRestrictedSetterPrivateKey) =
            makeAddrAndKey("isCreationRestrictedSetter");
        (isPausedSetter, isPausedSetterPrivateKey) = makeAddrAndKey("isPausedSetter");
        (paramSetter, paramSetterPrivateKey) = makeAddrAndKey("paramSetter");
        (userA, userAPrivateKey) = makeAddrAndKey("userA");
        rebasingToken = new MockRebasingERC20("RebasingToken", "rTKN", 18);
        weth = new MockWeth();
        buttonswapFactory = new ButtonswapFactory(feeToSetter, isCreationRestrictedSetter, isPausedSetter, paramSetter);
        ethButtonswapRouter = new ETHButtonswapRouter(address(buttonswapFactory), address(weth));
    }

    function test_WETH() public {
        assertEq(ethButtonswapRouter.WETH(), address(weth));
    }

    function test_constructor() public {
        assertEq(ethButtonswapRouter.WETH(), address(weth));
        assertEq(ethButtonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_receive_rejectNonWETHSender(address sender, uint256 ethAmount) public {
        // Making sure sender isn't the weth contract
        vm.assume(sender != address(weth));

        // Allocating ETH to the sender
        vm.deal(sender, ethAmount);

        // Sending ETH, ignoring data in return value
        vm.prank(sender);
        (bool sent, bytes memory returndata) = payable(address(ethButtonswapRouter)).call{value: ethAmount}("");
        assertTrue(!sent, "Expected call to fail");
        assertEq(
            returndata,
            abi.encodeWithSelector(IETHButtonswapRouterErrors.NonWETHSender.selector),
            "Expected revert reason to be NonWethSender()"
        );
    }

    function test_receive_acceptWETHSender(uint256 ethAmount) public {
        vm.deal(address(weth), ethAmount);
        vm.prank(address(weth));
        // Sending ETH, ignoring data in return value
        (bool sent,) = payable(address(ethButtonswapRouter)).call{value: ethAmount}("");
        assertTrue(sent, "Expected call to succeed");
    }

    // **** addLiquidityETH() ****

    function test_addLiquidityETH_createsPairIfNoneExists(uint256 amountTokenDesired, uint256 amountETHSent) public {
        // Minting enough for minimum liquidity requirement
        amountTokenDesired = bound(amountTokenDesired, 10000, type(uint112).max);
        amountETHSent = bound(amountETHSent, 10000, type(uint112).max);

        rebasingToken.mint(address(this), amountTokenDesired);
        rebasingToken.approve(address(ethButtonswapRouter), amountTokenDesired);
        vm.deal(address(this), amountETHSent);

        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Expect the factor to call createPair();
        vm.expectCall(
            address(buttonswapFactory),
            abi.encodeCall(ButtonswapFactory.createPair, (address(rebasingToken), address(weth)))
        );

        ethButtonswapRouter.addLiquidityETH{value: amountETHSent}(
            address(rebasingToken), amountTokenDesired, 0, 0, 700, userA, block.timestamp + 1
        );

        // Asserting one pair has been created
        assertEq(buttonswapFactory.allPairsLength(), 1);
    }

    function test_addLiquidityETH_pairExistsNoReservoirInsufficientTokenAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent,
        uint112 amountTokenMin
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // The calculated amount of ETH needed to match `amountTokenDesired` needs to be greater than `amountETHSent` to calibrate with `amountTokenDesired`
        vm.assume(amountTokenDesired > 0);
        uint256 matchingETHAmount = (amountTokenDesired * poolETH) / poolToken;
        vm.assume(matchingETHAmount > amountETHSent);

        // The calculated amount of rebasingToken needed to match `amountETHSent` is less than `amountTokenDesired`
        // but also being less than `amountTokenMin` triggers the error
        vm.assume(amountETHSent > 0);
        uint256 matchingTokenAmount = (amountETHSent * poolToken) / poolETH;

        vm.assume(matchingTokenAmount <= amountTokenDesired);
        vm.assume(matchingTokenAmount < amountTokenMin);
        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        ethButtonswapRouter.addLiquidityETH{value: amountETHSent}(
            address(rebasingToken), amountTokenDesired, amountTokenMin, 0, 700, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETH_pairExistsInsufficientETHAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent,
        uint112 amountETHMin
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // The calculated amount of ETH needed to match `amountTokenDesired` is less than `amountETHSent`
        // but also being less than `amountETHMin` triggers the error
        vm.assume(amountTokenDesired > 0);
        uint256 matchingETHAmount = (uint256(amountTokenDesired) * poolETH) / poolToken;
        vm.assume(matchingETHAmount <= amountETHSent);
        vm.assume(matchingETHAmount < amountETHMin);

        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        vm.deal(address(this), amountETHSent);
        ethButtonswapRouter.addLiquidityETH{value: amountETHSent}(
            address(rebasingToken), amountTokenDesired, 0, amountETHMin, 700, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETH_pairExistsNoReservoirAndOutputWithinBounds(
        uint256 poolToken,
        uint256 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Making sure the bounds are sufficient
        uint112 amountTokenMin = 10000;
        uint112 amountETHMin = 10000;

        // Setting up bounds to be properly ordered
        vm.assume(amountTokenMin < amountTokenDesired);
        vm.assume(amountETHMin < amountETHSent);

        // Ensuring the pair never has overflowing pool balances
        vm.assume(amountTokenDesired < type(uint112).max - poolToken);
        vm.assume(amountETHSent < type(uint112).max - poolETH);

        // Creating the pair with poolToken:poolETH price ratio
        createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // The matching amount of either token must fit within the bounds
        uint256 matchingTokenAmount = (uint256(amountETHSent) * poolToken) / poolETH;
        uint256 matchingETHAmount = (uint256(amountTokenDesired) * poolETH) / poolToken;
        vm.assume(
            (matchingTokenAmount <= amountTokenDesired && matchingTokenAmount > amountTokenMin)
                || (matchingETHAmount <= amountETHSent && matchingETHAmount > amountETHMin)
        );

        // Approving the router to take at most amountTokenDesired rebasingTokens and at most amountETHSent ETH
        rebasingToken.mint(address(this), amountTokenDesired);
        rebasingToken.approve(address(ethButtonswapRouter), amountTokenDesired);
        vm.deal(address(this), amountETHSent);

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountToken, uint256 amountETH,) = ethButtonswapRouter.addLiquidityETH{value: amountETHSent}(
            address(rebasingToken), amountTokenDesired, amountTokenMin, amountETHMin, 700, userA, block.timestamp + 1
        );

        // Assert that deposited amounts are within bounds
        assert(amountToken > amountTokenMin && amountToken <= amountTokenDesired);
        assert(amountETH > amountETHMin && amountETH <= amountETHSent);

        // Asserting that remaining tokens are returned to the caller
        assertEq(rebasingToken.balanceOf(address(this)), amountTokenDesired - amountToken);
        assertEq(address(this).balance, amountETHSent - amountETH, "Test contract should be refunded the remaining ETH");
    }

    function test_addLiquidityETH_pairExistsWithTokenReservoir(
        uint256 poolToken,
        uint256 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Ensuring that a rebasingToken-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying the rebase
        rebasingToken.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Attempting to withdraw the amounts in the pool (because it was a positive rebase, poolToken and poolETH are unchanged, but resToken has been created)
        amountTokenDesired = uint112(poolToken);
        amountETHSent = uint112(poolETH);

        // Ensuring the pair never has overflowing pool balances
        vm.assume(amountTokenDesired < type(uint112).max - poolToken);
        vm.assume(amountETHSent < type(uint112).max - poolETH);

        // Approving the router to take at most amountTokenDesired rebasingTokens and at most amountETHSent ETH
        rebasingToken.mint(address(this), amountTokenDesired);
        rebasingToken.approve(address(ethButtonswapRouter), amountTokenDesired);
        vm.deal(address(this), amountETHSent);

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountToken, uint256 amountETH,) = ethButtonswapRouter.addLiquidityETH{value: amountETHSent}(
            address(rebasingToken), amountTokenDesired, 0, 0, 700, userA, block.timestamp + 1
        );

        // Validating that it used amountTokenDesired and scaled down to calculate how much ETH to use
        assertEq(amountToken, amountTokenDesired, "Router should have used amountTokenDesired tokens");
        assertLt(amountETH, amountETHSent, "Router should have scaled down the ETH it used");
    }

    function test_addLiquidityETH_pairExistsWithETHReservoir(
        uint256 poolToken,
        uint256 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent,
        uint256 rebaseNumerator,
        uint256 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Ensuring that a ETH-reservoir is created with a negative rebase on the rebasingTokens (greater than 1/2)
        rebaseDenominator = bound(rebaseDenominator, 2, type(uint8).max);
        rebaseNumerator = bound(rebaseNumerator, rebaseDenominator / 2, rebaseDenominator - 1);

        // Applying the rebase
        rebasingToken.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Attempting to withdraw the amounts in the pool (because it was a positive rebase, poolToken and poolETH are unchanged, but resToken has been created)
        (uint256 newPoolToken, uint256 newPoolETH,,) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(rebasingToken), address(weth));
        amountTokenDesired = uint112(newPoolToken);
        amountETHSent = uint112(newPoolETH);

        // Ensuring the pair never has overflowing pool balances
        vm.assume(amountTokenDesired < type(uint112).max - poolToken);
        vm.assume(amountETHSent < type(uint112).max - poolETH);

        // Approving the router to take at most amountTokenDesired rebasingTokens and at most amountETHSent B tokens
        rebasingToken.mint(address(this), amountTokenDesired);
        rebasingToken.approve(address(ethButtonswapRouter), amountTokenDesired);
        vm.deal(address(this), amountETHSent);

        // Adding liquidity should succeed now. Not concerned with liquidity value
        (uint256 amountToken, uint256 amountETH,) = ethButtonswapRouter.addLiquidityETH{value: amountETHSent}(
            address(rebasingToken), amountTokenDesired, 0, 0, 700, userA, block.timestamp + 1
        );

        // Validating that it used amountETHSent and scaled down to calculate how much rebasingToken to use
        assertLt(amountToken, amountTokenDesired, "Router should have scaled down the rebasingTokens it used");
        assertEq(amountETH, amountETHSent, "Router should have used amountETHSent tokens");
    }

    function test_addLiquidityETH_movingAveragePriceOutOfBounds(
        bytes32 saltToken,
        uint256 poolToken,
        uint256 poolETH,
        uint256 swappedToken
    ) public {
        // Re-assigning token to fuzz the order of the tokens
        rebasingToken = new MockRebasingERC20{salt: saltToken}("Rebasing Token", "rTKN", 18);

        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);
        swappedToken = bound(swappedToken, poolToken / 100, poolToken - poolToken / 100);

        // Creating the pair with poolToken:poolETH price ratio
        createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Do a swap to move the moving average price out of bounds
        address[] memory path = new address[](2);
        path[0] = address(rebasingToken);
        path[1] = address(weth);
        rebasingToken.mint(address(this), swappedToken);
        rebasingToken.approve(address(ethButtonswapRouter), swappedToken);
        ethButtonswapRouter.swapExactTokensForETH(swappedToken, 0, path, address(this), block.timestamp + 1);

        // Figuring out what the value of movingAveragePriceThresholdBps to use to guarantee movingAveragePrice0 exceeds valid range
        (uint256 newPoolToken, uint256 newPoolETH,,) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(rebasingToken), address(weth));

        uint16 movingAveragePrice0ThresholdBps;
        // Deriving the threshold by setting it to 1 under how much the deviation actually was
        //        (pool1/pool0) = newPool1/newPool0 * (mT + BPS)/(BPS)
        //        pool1 * newPool0 * BPS = newPool1 * (mT + BPS) * pool0
        //        (mT) = (pool1 * newPool0 * BPS)/(newPool1 * pool0) - BPS
        if (address(rebasingToken) < address(weth)) {
            // token is token0
            vm.assume((poolETH * newPoolToken * BPS) > (newPoolETH * poolToken) * (BPS + 1));
            movingAveragePrice0ThresholdBps =
                uint16((poolETH * newPoolToken * BPS) / (newPoolETH * poolToken) - BPS - 1);
            vm.assume(0 < movingAveragePrice0ThresholdBps);
            vm.assume(movingAveragePrice0ThresholdBps < BPS);
        } else {
            // weth is token0
            vm.assume((poolToken * newPoolETH * BPS) > (newPoolToken * poolETH) * (BPS + 1));
            movingAveragePrice0ThresholdBps =
                uint16((poolToken * newPoolETH * BPS) / (newPoolToken * poolETH) - BPS - 1);
            vm.assume(0 < movingAveragePrice0ThresholdBps);
            vm.assume(movingAveragePrice0ThresholdBps < BPS);
        }

        // Approving the router to take at most newPoolToken tokens and at most newPoolETH eth
        rebasingToken.mint(address(this), newPoolToken);
        rebasingToken.approve(address(ethButtonswapRouter), newPoolToken);
        vm.deal(address(this), newPoolETH);

        // Adding liquidity with the same balances that are currently in the pair
        vm.expectRevert(IButtonswapRouterErrors.MovingAveragePriceOutOfBounds.selector);
        ethButtonswapRouter.addLiquidityETH{value: newPoolETH}(
            address(rebasingToken), newPoolToken, 0, 0, movingAveragePrice0ThresholdBps, userA, block.timestamp + 1
        );
    }

    // **** addLiquidityETHWithReservoir() ****

    function test_addLiquidityETHWithReservoir_revertsIfNoPairExists(uint112 amountTokenDesired, uint112 amountETHSent)
        public
    {
        // Minting enough for minimum liquidity requirement
        vm.assume(amountTokenDesired > 10000);
        vm.assume(amountETHSent > 10000);

        rebasingToken.mint(address(this), amountTokenDesired);
        rebasingToken.approve(address(ethButtonswapRouter), amountTokenDesired);
        vm.deal(address(this), amountETHSent);

        // Expect NoReservoir error to be thrown
        vm.expectRevert(IButtonswapRouterErrors.NoReservoir.selector);
        ethButtonswapRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
            address(rebasingToken), amountTokenDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_pairExistsButEmptyPools(
        uint112 amountTokenDesired,
        uint112 amountETHSent
    ) public {
        // Creating the pair without any liquidity
        buttonswapFactory.createPair(address(rebasingToken), address(weth));

        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonswapRouterErrors.NotInitialized.selector);
        ethButtonswapRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
            address(rebasingToken), amountTokenDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_pairExistsButMissingReservoir(
        uint256 poolToken,
        uint256 poolETH,
        uint112 amountTokenDesired,
        uint112 amountETHSent
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio. No rebase so no reservoir
        createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonswapRouterErrors.NoReservoir.selector);
        ethButtonswapRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
            address(rebasingToken), amountTokenDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirAWithInsufficientAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 amountETHSent
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Making sure amountETHSent is positive
        vm.assume(amountETHSent > 0);

        // Creating the pair with poolToken:poolETH price ratio
        createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Rebasing tokenA 10% up to create a rebasingToken reservoir
        rebasingToken.applyMultiplier(11, 10);

        // Calculating the optimalAmount of tokenA to amountETHSent and ensuring it's under `amountTokenMin`
        (, uint256 amountTokenOptimal) = ButtonswapLibrary.getMintSwappedAmounts(
            address(buttonswapFactory), address(weth), address(rebasingToken), amountETHSent
        );
        uint256 amountTokenMin = amountTokenOptimal + 1;

        vm.deal(address(this), amountETHSent);
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        ethButtonswapRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
            address(rebasingToken), 0, amountTokenMin, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirTokenWithSufficientAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountETHSent
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolToken < (type(uint112).max / rebaseNumerator) * rebaseDenominator);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Rebasing rebasingToken positively up to create a rebasingToken reservoir
        rebasingToken.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Getting reservoir size
        uint256 reservoirToken;
        (poolToken, poolETH, reservoirToken,) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(rebasingToken), address(weth));

        // Estimating how much of amountETHSent will be converted to rebasingTokens, and how much of the reservoir used
        uint256 liquidityOut;
        uint256 ETHToSwap;
        uint256 swappedReservoirAmountToken;
        (ETHToSwap, swappedReservoirAmountToken) = ButtonswapLibrary.getMintSwappedAmounts(
            address(buttonswapFactory), address(weth), address(rebasingToken), amountETHSent
        );

        // Making sure poolToken doesn't get Overflowed
        vm.assume(poolToken + swappedReservoirAmountToken < type(uint112).max);
        // Making sure poolETH doesn't get Overflowed
        vm.assume(poolETH + amountETHSent < type(uint112).max);
        // Making sure reservoirToken is not exceeded
        vm.assume(swappedReservoirAmountToken < reservoirToken);
        // Making sure the rest of reservoirToken can absorb the ephemeral sync that happens from the ETHToSwap transfer-in
        vm.assume((poolETH + amountETHSent) * poolToken <= (poolToken + reservoirToken) * poolETH);

        // Estimating how much liquidity will be minted
        liquidityOut = PairMath.getDualSidedMintLiquidityOutAmount(
            pair.totalSupply(),
            swappedReservoirAmountToken,
            amountETHSent - ETHToSwap,
            poolToken + reservoirToken - swappedReservoirAmountToken,
            poolETH + ETHToSwap
        );

        // Making sure minimum liquidity requirement is met
        vm.assume(liquidityOut > 0);
        // Making sure swappableReservoirLimit is not exceeded
        vm.assume(swappedReservoirAmountToken < pair.getSwappableReservoirLimit());

        // Dealing amountETHSent ETH
        vm.deal(address(this), amountETHSent);

        ethButtonswapRouter.addLiquidityETHWithReservoir{value: amountETHSent}(
            address(rebasingToken), 0, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirETHWithInsufficientAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 amountTokenDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Making sure amountTokenDesired is positive
        vm.assume(amountTokenDesired > 0);

        // Creating the pair with poolToken:poolETH price ratio
        createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Rebasing rebasingToken 10% down to create an ETH reservoir
        rebasingToken.applyMultiplier(9, 10);

        // Calculating the optimalAmount of ETH to amountTokenDesired and ensuring it's under `amountETHMin`
        (, uint256 amountETHOptimal) = ButtonswapLibrary.getMintSwappedAmounts(
            address(buttonswapFactory), address(rebasingToken), address(weth), amountTokenDesired
        );
        uint256 amountETHMin = amountETHOptimal + 1;

        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        ethButtonswapRouter.addLiquidityETHWithReservoir(
            address(rebasingToken), amountTokenDesired, 0, amountETHMin, userA, block.timestamp + 1
        );
    }

    function test_addLiquidityETHWithReservoir_usingReservoirETHWithSufficientAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator,
        uint112 amountTokenDesired
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Using a positive rebase on rebasingToken before we create the pair and then removing it immediately after
        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolToken < (type(uint112).max / rebaseNumerator) * rebaseDenominator);

        // Rebasing rebasingToken positively up before we create the pair
        rebasingToken.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Rebasing rebasingToken back down to create an ETH reservoir (this changes the price ratio)
        rebasingToken.applyMultiplier(rebaseDenominator, rebaseNumerator);

        // Getting reservoir size (and refetching poolToken and poolETH for accuracy)
        uint256 reservoirETH;
        (poolToken, poolETH,, reservoirETH) =
            ButtonswapLibrary.getLiquidityBalances(address(buttonswapFactory), address(rebasingToken), address(weth));

        // Estimating how much of amountTokenDesired will be converted to ETH, and how much of the reservoir used
        uint256 liquidityOut;
        uint256 tokenToSwap;
        uint256 swappedReservoirAmountETH;
        (tokenToSwap, swappedReservoirAmountETH) = ButtonswapLibrary.getMintSwappedAmounts(
            address(buttonswapFactory), address(rebasingToken), address(weth), amountTokenDesired
        );

        // Making sure poolETH doesn't get Overflowed
        vm.assume(poolETH + swappedReservoirAmountETH < type(uint112).max);
        // Making sure poolToken doesn't get Overflowed
        vm.assume(poolToken + amountTokenDesired < type(uint112).max);
        // Making sure reservoirETH is not exceeded
        vm.assume(swappedReservoirAmountETH < reservoirETH);
        // Making sure the rest of reservoirETH can absorb the ephemeral sync that happens from the tokenToSwap transfer-in
        vm.assume((poolToken + amountTokenDesired) * poolETH <= (poolETH + reservoirETH) * poolToken);

        // Estimating how much liquidity will be minted
        liquidityOut = PairMath.getDualSidedMintLiquidityOutAmount(
            pair.totalSupply(),
            amountTokenDesired - tokenToSwap,
            swappedReservoirAmountETH,
            poolToken + tokenToSwap,
            poolETH + reservoirETH - swappedReservoirAmountETH
        );

        // Making sure minimum liquidity requirement is met
        vm.assume(liquidityOut > 0);
        // Making sure swappableReservoirLimit is not exceeded
        vm.assume(swappedReservoirAmountETH < pair.getSwappableReservoirLimit());

        // Giving approval for amountTokenDesired rebasingToken
        rebasingToken.mint(address(this), amountTokenDesired);
        rebasingToken.approve(address(ethButtonswapRouter), amountTokenDesired);

        ethButtonswapRouter.addLiquidityETHWithReservoir(
            address(rebasingToken), amountTokenDesired, 0, 0, userA, block.timestamp + 1
        );
    }

    // **** removeLiquidityETH() ****

    function testFail_removeLiquidityETH_pairDoesNotExist(uint256 liquidity) public {
        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Attempt to remove liquidity but will revert since it's calling `transferFrom()` on an invalid address
        ethButtonswapRouter.removeLiquidityETH(address(rebasingToken), liquidity, 0, 0, userA, block.timestamp + 1);
    }

    function test_removeLiquidityETH_insufficientAAmount(uint256 poolToken, uint256 poolETH, uint112 liquidity)
        public
    {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolToken > totalLiquidity);
        vm.assume(liquidity * poolETH > totalLiquidity);

        // Calculating amountTokenMin to be one more than the amount of rebasingToken that would be removed
        uint256 amountTokenMin = (liquidity * poolToken) / (totalLiquidity) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(ethButtonswapRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        ethButtonswapRouter.removeLiquidityETH(
            address(rebasingToken), liquidity, amountTokenMin, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityETH_insufficientBAmount(uint256 poolToken, uint256 poolETH, uint112 liquidity)
        public
    {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolToken > totalLiquidity);
        vm.assume(liquidity * poolETH > totalLiquidity);

        // Calculating amountETHMin to be one more than the amount of ETH that would be removed
        uint256 amountETHMin = (liquidity * poolETH) / (totalLiquidity) + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(ethButtonswapRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        ethButtonswapRouter.removeLiquidityETH(
            address(rebasingToken), liquidity, 0, amountETHMin, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityETH_sufficientAmounts(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolToken > totalLiquidity);
        vm.assume(liquidity * poolETH > totalLiquidity);

        // Calculating rebasingToken and ETH to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountToken = (liquidity * poolToken) / (totalLiquidity);
        uint256 expectedAmountETH = (liquidity * poolETH) / (totalLiquidity);

        // Ensuring amountTokenMin and amountETHMin are smaller than the amount of rebasingToken and ETH that would be removed
        // Using bounds to reduce the number of vm assumptions needed
        amountTokenMin = bound(amountTokenMin, 0, expectedAmountToken);
        amountETHMin = bound(amountETHMin, 0, expectedAmountETH);

        // Giving permission to the pair to burn liquidity
        pair.approve(address(ethButtonswapRouter), liquidity);

        (uint256 amountToken, uint256 amountETH) = ethButtonswapRouter.removeLiquidityETH(
            address(rebasingToken), liquidity, amountTokenMin, amountETHMin, userA, block.timestamp + 1
        );

        // Ensuring amountToken and amountETH are as expected
        assertEq(amountToken, expectedAmountToken, "Did not remove expected amount of rebasingToken");
        assertEq(amountETH, expectedAmountETH, "Did not remove expected amount of ETH");
    }

    // **** removeLiquidityETHFromReservoir() ****

    function testFail_removeLiquidityETHFromReservoir_pairDoesNotExist(uint256 liquidity) public {
        // Validating no pairs exist before call
        assertEq(buttonswapFactory.allPairsLength(), 0);

        // Attempt to remove liquidity but will revert since it's calling `transferFrom()` on an invalid address
        ethButtonswapRouter.removeLiquidityETHFromReservoir(
            address(rebasingToken), liquidity, 0, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityETHFromReservoir_insufficientTokenAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring that a rebasingToken-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying a positive rebase to create an rebasingToken-reservoir
        rebasingToken.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Calculating expectedAmountOutToken and swappedReservoirAmountToken
        (uint256 expectedAmountOutToken, uint256 swappedReservoirAmountToken) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(rebasingToken), address(weth), liquidity
        );

        // Ensuring `InsufficientLiquidityBurned()` error not thrown
        vm.assume(expectedAmountOutToken > 0);

        // Ensuring swappedReservoirAmountToken is less than the limit
        vm.assume(swappedReservoirAmountToken < pair.getSwappableReservoirLimit());

        // Ensuring expectedAmountOutToken is less than that of the reservoir
        (uint256 reservoirToken,) =
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(rebasingToken), address(weth));
        vm.assume(expectedAmountOutToken < reservoirToken);

        // Calculating amountTokenMin to be one more than the amount of rebasingToken that would be removed
        uint256 amountTokenMin = expectedAmountOutToken + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(ethButtonswapRouter), liquidity);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        ethButtonswapRouter.removeLiquidityETHFromReservoir(
            address(rebasingToken), liquidity, amountTokenMin, 0, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityETHFromReservoir_insufficientETHAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Using a positive rebase on rebasingToken before we create the pair and then removing it immediately after
        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolToken < (type(uint112).max / rebaseNumerator) * rebaseDenominator);

        // Rebasing rebasingToken positively up before we create the pair
        rebasingToken.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Rebasing rebasingToken back down to create an ETH reservoir (this changes the price ratio)
        rebasingToken.applyMultiplier(rebaseDenominator, rebaseNumerator);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Calculating expectedAmountOutETH and swappedReservoirAmountETH
        (uint256 expectedAmountOutETH, uint256 swappedReservoirAmountETH) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(weth), address(rebasingToken), liquidity
        );

        // Ensuring `InsufficientLiquidityBurned()` error not thrown
        vm.assume(expectedAmountOutETH > 0);

        // Ensuring swappedReservoirAmountETH is less than the limit
        vm.assume(swappedReservoirAmountETH < pair.getSwappableReservoirLimit());

        // Ensuring expectedAmountOutETH is less than that of the reservoir
        (, uint256 reservoirETH) =
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(rebasingToken), address(weth));
        vm.assume(expectedAmountOutETH < reservoirETH);

        // Calculating amountETHMin to be one more than the amount of ETH that would be removed
        uint256 amountETHMin = expectedAmountOutETH + 1;

        // Giving permission to the pair to burn liquidity
        pair.approve(address(ethButtonswapRouter), liquidity);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        ethButtonswapRouter.removeLiquidityETHFromReservoir(
            address(rebasingToken), liquidity, 0, amountETHMin, userA, block.timestamp + 1
        );
    }

    function test_removeLiquidityETHFromReservoir_usingReservoirTokenWithSufficientAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring that a rebasingToken-reservoir is created with a positive rebase
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(rebaseDenominator > 0);

        // Applying a positive rebase to create an rebasingToken-reservoir
        rebasingToken.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Calculating expectedAmountOutToken and swappedReservoirAmountToken
        (uint256 expectedAmountOutToken, uint256 swappedReservoirAmountToken) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(rebasingToken), address(weth), liquidity
        );

        // Ensuring `InsufficientLiquidityBurned()` error not thrown
        vm.assume(expectedAmountOutToken > 0);

        // Ensuring swappedReservoirAmountToken is less than the limit
        vm.assume(swappedReservoirAmountToken < pair.getSwappableReservoirLimit());

        // Ensuring expectedAmountOutToken is less than that of the reservoir
        (uint256 reservoirToken,) =
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(rebasingToken), address(weth));
        vm.assume(expectedAmountOutToken < reservoirToken);

        // Giving permission to the pair to burn liquidity
        pair.approve(address(ethButtonswapRouter), liquidity);

        (uint256 amountOutToken, uint256 amountOutETH) = ethButtonswapRouter.removeLiquidityETHFromReservoir(
            address(rebasingToken), liquidity, 0, 0, userA, block.timestamp + 1
        );

        // Checking that the correct amount of rebasingToken was removed and no ETH was removed
        assertEq(amountOutToken, expectedAmountOutToken, "Incorrect amount of rebasingToken removed");
        assertEq(amountOutETH, 0, "Incorrect amount of ETH removed");
    }

    function test_removeLiquidityETHFromReservoir_usingReservoirETHWithSufficientAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity,
        uint8 rebaseNumerator,
        uint8 rebaseDenominator
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Using a positive rebase on rebasingToken before we create the pair and then removing it immediately after
        // Ensuring it's a positive rebase that isn't too big
        vm.assume(rebaseDenominator > 0);
        vm.assume(rebaseNumerator > rebaseDenominator);
        vm.assume(poolToken < (type(uint112).max / rebaseNumerator) * rebaseDenominator);

        // Rebasing rebasingToken positively up before we create the pair
        rebasingToken.applyMultiplier(rebaseNumerator, rebaseDenominator);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair,) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);

        // Rebasing rebasingToken back down to create an ETH reservoir (this changes the price ratio)
        rebasingToken.applyMultiplier(rebaseDenominator, rebaseNumerator);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Calculating expectedAmountOutETH and swappedReservoirAmountETH
        (uint256 expectedAmountOutETH, uint256 swappedReservoirAmountETH) = ButtonswapLibrary.getBurnSwappedAmounts(
            address(buttonswapFactory), address(weth), address(rebasingToken), liquidity
        );

        // Ensuring `InsufficientLiquidityBurned()` error not thrown
        vm.assume(expectedAmountOutETH > 0);

        // Ensuring swappedReservoirAmountETH is less than the limit
        vm.assume(swappedReservoirAmountETH < pair.getSwappableReservoirLimit());

        // Ensuring expectedAmountOutETH is less than that of the reservoir
        (, uint256 reservoirETH) =
            ButtonswapLibrary.getReservoirs(address(buttonswapFactory), address(rebasingToken), address(weth));
        vm.assume(expectedAmountOutETH < reservoirETH);

        // Giving permission to the pair to burn liquidity
        pair.approve(address(ethButtonswapRouter), liquidity);

        (uint256 amountOutToken, uint256 amountOutETH) = ethButtonswapRouter.removeLiquidityETHFromReservoir(
            address(rebasingToken), liquidity, 0, 0, userA, block.timestamp + 1
        );

        // Checking that the correct amount of ETH was removed and no rebasingToken was removed
        assertEq(amountOutToken, 0, "Incorrect amount of rebasingToken removed");
        assertEq(amountOutETH, expectedAmountOutETH, "Incorrect amount of ETH removed");
    }

    // **** removeLiquidityETHWithPermit() ****
    // Note: Can't create permissions without an existing pair, so need to test against pairDoesNotExist case

    function test_removeLiquidityETHWithPermit_usingMaxPermissionButInsufficientTokenAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolToken > totalLiquidity);
        vm.assume(liquidity * poolETH > totalLiquidity);

        // Calculating amountTokenMin to be one more than the amount of A that would be removed
        uint256 amountTokenMin = (liquidity * poolToken) / (totalLiquidity) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        ethButtonswapRouter.removeLiquidityETHWithPermit(
            address(rebasingToken), liquidity, amountTokenMin, 0, userA, block.timestamp + 1, true, v, r, s
        );
    }

    function test_removeLiquidityETHWithPermit_usingSpecificPermissionButInsufficientTokenAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolToken > totalLiquidity);
        vm.assume(liquidity * poolETH > totalLiquidity);

        // Calculating amountTokenMin to be one more than the amount of A that would be removed
        uint256 amountTokenMin = (liquidity * poolToken) / (totalLiquidity) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientAAmount.selector);
        vm.prank(userA);
        ethButtonswapRouter.removeLiquidityWithPermit(
            address(rebasingToken),
            address(weth),
            liquidity,
            amountTokenMin,
            0,
            userA,
            block.timestamp + 1,
            false,
            v,
            r,
            s
        );
    }

    function test_removeLiquidityETHWithPermit_usingMaxPermissionButInsufficientETHAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolToken > totalLiquidity);
        vm.assume(liquidity * poolETH > totalLiquidity);

        // Calculating amountETHMin to be one more than the amount of ETH that would be removed
        uint256 amountETHMin = (liquidity * poolETH) / (totalLiquidity) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        ethButtonswapRouter.removeLiquidityETHWithPermit(
            address(rebasingToken), liquidity, 0, amountETHMin, userA, block.timestamp + 1, true, v, r, s
        );
    }

    function test_removeLiquidityETHWithPermit_usingSpecificPermissionButInsufficientETHAmount(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolToken > totalLiquidity);
        vm.assume(liquidity * poolETH > totalLiquidity);

        // Calculating amountETHMin to be one more than the amount of ETH that would be removed
        uint256 amountETHMin = (liquidity * poolETH) / (totalLiquidity) + 1;

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientBAmount()` error
        vm.expectRevert(IButtonswapRouterErrors.InsufficientBAmount.selector);
        vm.prank(userA);
        ethButtonswapRouter.removeLiquidityETHWithPermit(
            address(rebasingToken), liquidity, 0, amountETHMin, userA, block.timestamp + 1, false, v, r, s
        );
    }

    function test_removeLiquidityETHWithPermit_usingMaxPermissionAndSufficientAmounts(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolToken > totalLiquidity);
        vm.assume(liquidity * poolETH > totalLiquidity);

        // Calculating amountToken and amountETH to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountToken = (liquidity * poolToken) / (totalLiquidity);
        uint256 expectedAmountETH = (liquidity * poolETH) / (totalLiquidity);

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, type(uint256).max, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.prank(userA);
        (uint256 amountToken, uint256 amountETH) = ethButtonswapRouter.removeLiquidityETHWithPermit(
            address(rebasingToken), liquidity, 0, 0, userA, block.timestamp + 1, true, v, r, s
        );

        // Ensuring amountToken and amountETH are as expected
        assertEq(amountToken, expectedAmountToken, "Did not remove expected amount of rebasingToken");
        assertEq(amountETH, expectedAmountETH, "Did not remove expected amount of ETH");
    }

    function test_removeLiquidityETHWithPermit_usingSpecificPermissionAndSufficientAmounts(
        uint256 poolToken,
        uint256 poolETH,
        uint112 liquidity
    ) public {
        // Minting enough for minimum liquidity requirement
        poolToken = bound(poolToken, 10000, type(uint112).max);
        poolETH = bound(poolETH, 10000, type(uint112).max);

        // Creating the pair with poolToken:poolETH price ratio
        (IButtonswapPair pair, uint256 liquidityOut) = createAndInitializePairETH(rebasingToken, poolToken, poolETH);
        // Having userA own the liquidity
        pair.transfer(userA, liquidityOut);

        // Getting total burnable liquidity
        uint256 totalLiquidity = pair.totalSupply();
        uint256 burnableLiquidity = totalLiquidity - 1000;

        // Making sure liquidity is less than burnableLiquidity
        vm.assume(liquidity < burnableLiquidity);

        // Ensuring liquidity burned doesn't remove too little to throw `InsufficientLiquidityBurned()` error
        vm.assume(liquidity * poolToken > totalLiquidity);
        vm.assume(liquidity * poolETH > totalLiquidity);

        // Calculating amountToken and amountETH to be removed corresponding to the amount of liquidity burned
        uint256 expectedAmountToken = (liquidity * poolToken) / (totalLiquidity);
        uint256 expectedAmountETH = (liquidity * poolETH) / (totalLiquidity);

        // Generating the v,r,s signature for userA to allow access to the pair
        (uint8 v, bytes32 r, bytes32 s) = generateUserAPermitSignature(pair, liquidity, block.timestamp + 1);

        // Expecting to revert with `InsufficientAAmount()` error
        vm.prank(userA);
        (uint256 amountToken, uint256 amountETH) = ethButtonswapRouter.removeLiquidityETHWithPermit(
            address(rebasingToken), liquidity, 0, 0, userA, block.timestamp + 1, false, v, r, s
        );

        // Ensuring amountToken and amountETH are as expected
        assertEq(amountToken, expectedAmountToken, "Did not remove expected amount of A");
        assertEq(amountETH, expectedAmountETH, "Did not remove expected amount of B");
    }

    // **** swapExactETHForTokens() ****

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
        ethButtonswapRouter.swapExactETHForTokens{value: amountETHSent}(
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
        ethButtonswapRouter.swapExactETHForTokens{value: amountETHSent}(
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
        (uint256[] memory amounts) = ethButtonswapRouter.swapExactETHForTokens{value: amountETHSent}(
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

    // **** swapTokensForExactETH() ****

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
        ethButtonswapRouter.swapTokensForExactETH(amountOut, amountInMax, path, address(this), block.timestamp + 1);
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
        ethButtonswapRouter.swapTokensForExactETH(amountOut, amountInMax, path, address(this), block.timestamp + 1);
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
        MockRebasingERC20(path[0]).approve(address(ethButtonswapRouter), amountInMax);

        (uint256[] memory amounts) =
            ethButtonswapRouter.swapTokensForExactETH(amountOut, amountInMax, path, address(this), block.timestamp + 1);

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

    // **** swapExactTokensForETH() ****

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
        ethButtonswapRouter.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), block.timestamp + 1);
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
        ethButtonswapRouter.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), block.timestamp + 1);
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
        MockRebasingERC20(path[0]).approve(address(ethButtonswapRouter), amountIn);

        (uint256[] memory amounts) =
            ethButtonswapRouter.swapExactTokensForETH(amountIn, amountOutMin, path, address(this), block.timestamp + 1);

        // Checking that the amounts in the trade are as expected
        assertEq(amounts, expectedAmounts, "Amounts in the trade are not as expected");

        // Checking that callee received the expected amount of the final token
        assertEq(address(this).balance, amounts[amounts.length - 1], "Did not receive expected amount of ETH");
    }

    // **** swapETHForExactTokens() ****

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
        ethButtonswapRouter.swapETHForExactTokens(amountOut, path, address(this), block.timestamp + 1);
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
        ethButtonswapRouter.swapETHForExactTokens(amountOut, path, address(this), block.timestamp + 1);
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
        (uint256[] memory amounts) = ethButtonswapRouter.swapETHForExactTokens{value: amountETHSent}(
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
}
