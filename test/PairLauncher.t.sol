// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";
import {MockRebasingERC20} from "buttonswap-periphery_mock-contracts/MockRebasingERC20.sol";
import {PairLauncher} from "../src/PairLauncher.sol";

contract PairLauncherTest is Test {
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
    PairLauncher public pairLauncher;

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

        vm.prank(isCreationRestrictedSetter);
        buttonswapFactory.setIsCreationRestricted(true);

        pairLauncher = new PairLauncher(userA, isCreationRestrictedSetter, address(buttonswapFactory));
    }

    function test_constructor() public {
        assertEq(address(pairLauncher.factory()), address(buttonswapFactory));
        assertEq(pairLauncher.launcher(), userA);
        assertEq(pairLauncher.originalIsCreationRestrictedSetter(), isCreationRestrictedSetter);
    }

    function test_flow1(bytes32 saltA, bytes32 saltB, uint256 amountA, uint256 amountB) public {
        // Re-assigning tokenA and tokenB to fuzz the order of the tokens
        tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        vm.prank(userA);
        pairLauncher.enqueuePair(address(tokenA), address(tokenB), amountA, amountB);

        (address tokenA1, address tokenB1, uint256 amountA1, uint256 amountB1) = pairLauncher.pairStack(0);
        assertEq(tokenA1, address(tokenA));
        assertEq(tokenB1, address(tokenB));
        assertEq(amountA1, amountA);
        assertEq(amountB1, amountB);
    }

    function test_flow2(bytes32 saltA, bytes32 saltB, uint256 amountA, uint256 amountB) public {
        // Re-assigning tokenA and tokenB to fuzz the order of the tokens
        tokenA = new MockRebasingERC20{salt: saltA}("Token A", "TKN_A", 18);
        tokenB = new MockRebasingERC20{salt: saltB}("Token B", "TKN_B", 18);

        amountA = bound(amountA, 10000, type(uint112).max);
        amountB = bound(amountB, 10000, type(uint112).max);

        vm.prank(userA);
        pairLauncher.enqueuePair(address(tokenA), address(tokenB), amountA, amountB);

        // Minting enough tokens for userA to use
        tokenA.mint(userA, amountA);
        vm.prank(userA);
        tokenA.approve(address(pairLauncher), amountA);
        tokenB.mint(userA, amountB);
        vm.prank(userA);
        tokenB.approve(address(pairLauncher), amountB);

        // CreationRestrictedSetter transferring permissions
        vm.prank(isCreationRestrictedSetter);
        buttonswapFactory.setIsCreationRestrictedSetter(address(pairLauncher));

        assertEq(buttonswapFactory.isCreationRestrictedSetter(), address(pairLauncher));

        // userA calling batchCreate5
        vm.prank(userA);
        pairLauncher.batchCreate5();

        // Returning permissions
        vm.prank(userA);
        pairLauncher.returnPermissions();

        // Validating that the permissions were returned
        assertEq(buttonswapFactory.isCreationRestrictedSetter(), isCreationRestrictedSetter);

        // Self-destructing
        vm.prank(userA);
        pairLauncher.destroy();
    }
}
