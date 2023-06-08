// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IButtonswapRouterErrors.sol";

interface IRootButtonswapRouter is IButtonswapRouterErrors {
    /**
     * @notice Returns the address of the Buttonswap Factory
     * @return factory The address of the Buttonswap Factory
     */
    function factory() external view returns (address factory);

    /**
     * @notice Returns the address of the WETH token
     * @return WETH The address of the WETH token
     */
    function WETH() external view returns (address WETH);
}
