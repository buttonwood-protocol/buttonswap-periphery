// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

interface IGenericButtonswapRouterErrors {
    // **** WETH Errors **** //
    /**
     * @dev Thrown when ETH is sent by address other than WETH contract
     * @param sender The sender of the ETH
     */
    error NonWETHSender(address sender);
    /// @notice WETH transfer failed
    //    error FailedWETHTransfer();
    /**
     * @notice Thrown when a different token address is provided where WETH address is expected\
     * @param weth The address of WETH
     * @param token The address of the token
     */
    error NonWethToken(address weth, address token);
    /**
     * @notice Thrown when input is a token instead of should be ETH (0x address)
     * @param token The address of the token
     */
    error NonEthToken(address token);

    // **** Button Errors **** //
    /**
     * @notice Thrown when the underlying token doesn't match that of the buttonToken
     * @param buttonToken The address of the buttonToken
     * @param underlyingToken The address of the underlying token
     * @param token The address of the token provided
     */
    error IncorrectButtonUnderlying(address buttonToken, address underlyingToken, address token);

    // **** IERC20 Errors **** //
    /**
     * @notice Thrown when the amountIn doesn't match the router's current balance of IERC20 token
     * @param token The address of the token
     * @param balance The balance of the token
     */
    error IncorrectBalance(address token, uint256 balance, uint256 amountIn);

    // **** Swap Errors **** //
    /**
     * @notice Thrown when the calculated input amount exceeds the specified maximum
     * @param amountInMax The maximum amount of input token
     * @param amount The amount of input token
     */
    error ExcessiveInputAmount(uint256 amountInMax, uint256 amount);
    /**
     * @notice Thrown when insufficient tokens are returned in an operation
     * @param amountOutMin The minimum amount of output token
     * @param amount The amount of output token
     */
    error InsufficientOutputAmount(uint256 amountOutMin, uint256 amount);
    /**
     * @notice Thrown when the deadline is exceeded
     * @param deadline The deadline
     * @param timestamp The current timestamp
     */
    error Expired(uint256 deadline, uint256 timestamp);
}
