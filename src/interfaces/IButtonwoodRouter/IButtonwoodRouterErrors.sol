// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IButtonwoodRouterErrors {
    /// @Notice Deadline was exceeded
    error Expired();
    /// @Notice Insufficient amount of token A available
    error InsufficientAAmount();
    /// @Notice Insufficient amount of token B available
    error InsufficientBAmount();
    /// @Notice Neither token in the pool has the required reservoir
    error NoReservoir();
    /// @Notice Pools are not initialized
    error NotInitialized();
    /// @Notice Insufficient amount of token A in the reservoir
    error InsufficientAReservoir();
    /// @Notice Insufficient amount of token B in the reservoir
    error InsufficientBReservoir();
    /// @Notice Insufficient tokens returned from operation
    error InsufficientOutputAmount();
    /// @Notice Required input amount exceeds specified maximum
    error ExcessiveInputAmount();
    /// @Notice Invalid path provided
    error InvalidPath();
}
