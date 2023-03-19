// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IButtonwoodRouterErrors {
    /// @Notice Deadline was exceeded
    error Expired();
    error InsufficientAAmount();
    error InsufficientBAmount();
    error NoReservoir();
    error NotInitialized();
    error InsufficientAReservoir();
    error InsufficientBReservoir();
    error InsufficientOutputAmount();
    error ExcessiveInputAmount();
    error InvalidPath();

}