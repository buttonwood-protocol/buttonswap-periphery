// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.13;

// Interface taken from https://docs.blast.io/building/guides/weth-yield
enum YieldMode {
    AUTOMATIC,
    VOID,
    CLAIMABLE
}

interface IBlastERC20Rebasing {
    // changes the yield mode of the caller and update the balance
    // to reflect the configuration
    function configure(YieldMode) external returns (uint256);
    // "claimable" yield mode accounts can call this this claim their yield
    // to another address
    function claim(address recipient, uint256 amount) external returns (uint256);
    // read the claimable amount for an account
    function getClaimableAmount(address account) external view returns (uint256);
}

contract MockBlastERC20Rebasing is IBlastERC20Rebasing {
    YieldMode public mockMode;

    function configure(YieldMode mode) external returns (uint256) {
        mockMode = mode;
        return 0;
    }

    function claim(address, /*recipient*/ uint256 /*amount*/ ) external pure returns (uint256) {
        return 0;
    }

    function getClaimableAmount(address /*account*/ ) external pure returns (uint256) {
        return 0;
    }
}
