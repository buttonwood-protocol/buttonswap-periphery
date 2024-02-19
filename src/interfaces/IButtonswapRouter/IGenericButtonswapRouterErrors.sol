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
     * @notice Thrown when a different token address is provided where WETH address is expected
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
     * @param underlyingToken The address of the underlying token
     * @param buttonToken The address of the buttonToken
     */
    error IncorrectButtonPairing(address underlyingToken, address buttonToken);

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

    // **** AddLiquidity Errors **** //
    /**
     * @notice movingAveragePrice0 is out of specified bounds
     * @param pool0 The amount in pool0
     * @param pool1 The amount in pool1
     * @param movingAveragePrice0 The current movingAveragePrice0 of the pair
     * @param movingAveragePrice0ThresholdBps The threshold of deviation of movingAveragePrice0 from the pool price
     */
    error MovingAveragePriceOutOfBounds(
        uint256 pool0, uint256 pool1, uint256 movingAveragePrice0, uint16 movingAveragePrice0ThresholdBps
    );

    // **** AddLiquidity/RemoveLiquidity Errors **** //
    /**
     * @notice Insufficient amount of token available
     * @param token The address of token
     * @param amount The amount of token available
     * @param requiredAmount The amount of token required
     */
    error InsufficientTokenAmount(address token, uint256 amount, uint256 requiredAmount);

    /**
     * @notice Pair does not exist
     * @param tokenA The address of tokenA
     * @param tokenB The address of tokenB
     */
    error PairDoesNotExist(address tokenA, address tokenB);

    /**
     * @notice Pair has not yet been initialized
     */
    error NotInitialized(address pair);

    /**
     * @notice Neither token in the pair has a non-empty reservoir
     */
    error NoReservoir(address pair);
}
