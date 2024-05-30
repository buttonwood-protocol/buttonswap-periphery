// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IUSDM {
    function convertToShares(uint256 amount) external view returns (uint256);

    function convertToTokens(uint256 shares) external view returns (uint256);

    function sharesOf(address account) external view returns (uint256);

    function mint(address to, uint256 amount) external;
}
