// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

library ButtonswapOperations {
    enum Swap {
        SWAP,
        WRAP_BUTTON,
        UNWRAP_BUTTON,
        WRAP_WETH,
        UNWRAP_WETH
    }

    // ToDo: Potentially redundant
    enum AddLiquidity {
        ADD_LIQUIDITY,
        ADD_LIQUIDITY_WITH_RESERVOIR
    }

    // ToDo: Potentially redundant
    enum RemoveLiquidity {
        BURN_LIQUIDITY,
        BURN_LIQUIDITY_WITH_RESERVOIR
    }
}
