// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

library ButtonswapOperations {
    enum Swap {
        SWAP,
        WRAP_BUTTON,
        UNWRAP_BUTTON,
        WRAP_WETH,
        UNWRAP_WETH,
        USDM_SWAP
    }

    enum Liquidity {
        DUAL,
        SINGLE
    }
}
