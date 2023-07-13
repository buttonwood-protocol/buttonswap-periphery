// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IGenericButtonswapRouterErrors {
    // **** WETH Errors **** //
    /// @notice Only WETH contract can send ETH to contract
    error NonWETHSender();
    /// @notice WETH transfer failed
    error FailedWETHTransfer();
    /// @notice Address is not WETH
    error NonWethToken();
    /// @notice Input should be ETH, not a token
    error NonEthToken();

    // **** Button Errors **** //
    /// @notice Underlying token doesn't match
    error IncorrectButtonUnderlying();

    // **** IERC20 Errors **** //
    /// @notice Incorrect balance of IERC20 token
    error IncorrectBalance();

    // **** Swap Errors **** //
    /// @notice Insufficient tokens returned from operation
    error InsufficientOutputAmount();
    /// @notice Deadline was exceeded
    error Expired();
}
