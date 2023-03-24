// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ButtonwoodLibrary} from "../../src/libraries/ButtonwoodLibrary.sol";
import {ButtonswapFactory} from "buttonswap-core/ButtonswapFactory.sol";
import {ButtonswapPair} from "buttonswap-core/ButtonswapPair.sol";
import {MockERC20} from "mock-contracts/MockERC20.sol";

contract ButtonwoodLibraryTest is Test {
    address public userA = 0x000000000000000000000000000000000000000A;

    ButtonswapFactory public buttonswapFactory;

    function createTokenAtAddress(address addr, string memory name, string memory symbol) private returns (MockERC20) {
        // Keeping addr out of the bad address range
        vm.assume(addr > address(10000));

        MockERC20 token = new MockERC20(name, symbol);

        // Copying over token name
        vm.store(addr, bytes32(uint256(3)), vm.load(address(token), bytes32(uint256(3))));
        // Copying over token symbol
        vm.store(addr, bytes32(uint256(4)), vm.load(address(token), bytes32(uint256(4))));
        // Copying over token _mintableBalance
        vm.store(addr, bytes32(uint256(5)), vm.load(address(token), bytes32(uint256(5))));

        // Copying over the code
        vm.etch(addr, address(token).code);
        return MockERC20(addr);
    }

    function setUp() public {
        buttonswapFactory = new ButtonswapFactory(address(this));
    }

    function test_sortTokens_valid_addresses(address tokenA, address tokenB) public {
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

    function test_sortTokens_identical_addresses(address token) public {
        // Ensuring the IdenticalAddresses error is thrown
        vm.expectRevert(ButtonwoodLibrary.IdenticalAddresses.selector);
        ButtonwoodLibrary.sortTokens(token, token);
    }

    function test_sortTokens_zero_address(address token, bool firstTokenIsZero) public {
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
        console.logString("hello");
        // Ensuring that the addresses are not equal
        vm.assume(tokenA != tokenB);
        // Ensuring that the addresses are not zero
        vm.assume(tokenA != address(0));
        vm.assume(tokenB != address(0));

        // Create the pair with the factory and two tokens
        assertEq(buttonswapFactory.allPairsLength(), 0);
        address factoryPair = buttonswapFactory.createPair(tokenA, tokenB);
        assertEq(buttonswapFactory.allPairsLength(), 1);

        // Call the pairFor function to get the pair address
        address pair = ButtonwoodLibrary.pairFor(address(buttonswapFactory), tokenA, tokenB);

        // Assert that the pair address matches the factory pair address
        assertEq(pair, factoryPair);
    }

    function test_getPools_empty_pools(address addressA, address addressB) public {
        // Ensuring that the addresses are not equal
        vm.assume(addressA != addressB);

        // Don't need to confirm addresses are not zero since it's checked in the createTokenAtAddress function
        MockERC20 tokenA = createTokenAtAddress(addressA, "Token A", "TKA");
        MockERC20 tokenB = createTokenAtAddress(addressB, "Token B", "TKB");

        // Create the pair with the factory and two tokens
        buttonswapFactory.createPair(address(tokenA), address(tokenB));

        // Call the getPools function to get the pools
        (uint256 poolA, uint256 poolB) =
            ButtonwoodLibrary.getPools(address(buttonswapFactory), address(tokenA), address(tokenB));

        // Assert that the pool amounts equal the token amounts minted
        assertEq(poolA, 0);
        assertEq(poolB, 0);
    }

    function test_getPools_nonEmpty_pools(address addressA, address addressB, uint112 amountA, uint112 amountB)
        public
    {
        // Ensuring that the addresses are not equal
        vm.assume(addressA != addressB);
        // Ensuring that amountA and amountB are enough to mint minimum liquidity
        vm.assume(amountA > 1000);
        vm.assume(amountB > 1000);

        // Don't need to confirm addresses are not zero since it's checked in the createTokenAtAddress function
        MockERC20 tokenA = createTokenAtAddress(addressA, "Token A", "TKA");
        MockERC20 tokenB = createTokenAtAddress(addressB, "Token B", "TKB");

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
}
