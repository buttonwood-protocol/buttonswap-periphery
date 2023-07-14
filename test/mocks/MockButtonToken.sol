// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IButtonToken} from "../../src/interfaces/IButtonToken.sol";
import {TransferHelper} from "../../src/libraries/TransferHelper.sol";

// ToDo: Migrate to an actual MockButtonToken implementation from mock-contracts repo (this one has no rebasing)
contract MockButtonToken is IButtonToken {
    // PLEASE READ BEFORE CHANGING ANY ACCOUNTING OR MATH
    // We make the following guarantees:
    // - If address 'A' transfers x button tokens to address 'B'.
    //   A's resulting external balance will be decreased by "precisely" x button tokens,
    //   and B's external balance will be "precisely" increased by x button tokens.
    // - If address 'A' deposits y underlying tokens,
    //   A's resulting underlying balance will increase by "precisely" y.
    // - If address 'A' withdraws y underlying tokens,
    //   A's resulting underlying balance will decrease by "precisely" y.
    //
    address public immutable override underlying;
    /// @dev internal balance, bits issued per account
    mapping(address => uint256) private _accountBits;
    mapping(address => mapping(address => uint256)) private allowance;

    constructor(address _underlying) {
        underlying = _underlying;
    }

    /// @notice Transfers underlying tokens from {msg.sender} to the contract and
    ///         mints wrapper tokens.
    /// @param amount The amount of wrapper tokens to mint.
    /// @return The amount of underlying tokens deposited.
    function mint(uint256 amount) external returns (uint256) {
        TransferHelper.safeTransferFrom(underlying, msg.sender, address(this), amount);
        _accountBits[msg.sender] += amount;
        return _accountBits[msg.sender];
    }

    /// @notice Burns all wrapper tokens from {msg.sender} and transfers
    ///         the underlying tokens back.
    /// @return The amount of underlying tokens withdrawn.
    function burnAll() external returns (uint256) {
        uint256 amount = _accountBits[msg.sender];
        _accountBits[msg.sender] = 0;
        TransferHelper.safeTransfer(underlying, msg.sender, amount);
        return amount;
    }

    /// @notice Transfers underlying tokens from {msg.sender} to the contract and
    ///         mints wrapper tokens to the specified beneficiary.
    /// @param uAmount The amount of underlying tokens to deposit.
    /// @return The amount of wrapper tokens mint.
    function deposit(uint256 uAmount) external returns (uint256) {
        TransferHelper.safeTransferFrom(underlying, msg.sender, address(this), uAmount);
        _accountBits[msg.sender] += uAmount;
        return _accountBits[msg.sender];
    }

    /// @notice Burns all wrapper tokens from {msg.sender} and transfers
    ///         the underlying tokens back.
    /// @return The amount of wrapper tokens burnt.
    function withdrawAll() external returns (uint256) {
        uint256 amount = _accountBits[msg.sender];
        _accountBits[msg.sender] = 0;
        TransferHelper.safeTransfer(underlying, msg.sender, amount);
        return amount;
    }

    //--------------------------------------------------------------------------
    // ButtonWrapper view methods

    /// @return The total underlying tokens held by the wrapper contract.
    function totalUnderlying() external view returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    }

    /// @param who The account address.
    /// @return The underlying token balance of the account.
    function balanceOfUnderlying(address who) external view returns (uint256) {
        return _accountBits[who];
    }

    /// @param uAmount The amount of underlying tokens.
    /// @return The amount of wrapper tokens exchangeable.
    function underlyingToWrapper(uint256 uAmount) external pure returns (uint256) {
        return uAmount;
    }

    /// @param amount The amount of wrapper tokens.
    /// @return The amount of underlying tokens exchangeable.
    function wrapperToUnderlying(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    //--------------------------------------------------------------------------
    // IERC20 methods

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        assert(_accountBits[msg.sender] >= amount);
        _accountBits[msg.sender] -= amount;
        _accountBits[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        assert(allowance[from][to] >= amount);
        assert(_accountBits[from] >= amount);
        allowance[from][to] -= amount;
        _accountBits[from] -= amount;
        _accountBits[to] += amount;
        return true;
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return _accountBits[account];
    }
}
