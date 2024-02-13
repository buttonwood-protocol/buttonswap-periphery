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

    // ToDo: Refactor these to just say "Liquidity" and re-use them. Dual + Single.
    // ToDo: Potentially redundant
    enum AddLiquidity {
        ADD_LIQUIDITY, // ToDo: Rename to dual/single
        ADD_LIQUIDITY_WITH_RESERVOIR
    }

    // ToDo: Potentially redundant
    enum RemoveLiquidity {
        REMOVE_LIQUIDITY, // ToDo: Rename to dual/single
        REMOVE_LIQUIDITY_WITH_RESERVOIR
    }
}
