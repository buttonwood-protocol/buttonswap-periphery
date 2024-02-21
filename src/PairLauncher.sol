// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IButtonswapFactory} from
    "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapFactory/IButtonswapFactory.sol";
import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

contract PairLauncher {
    struct PairData {
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
    }

    IButtonswapFactory public immutable factory;
    address public immutable launcher;
    address public immutable originalIsCreationRestrictedSetter;
    PairData[] public pairStack;

    modifier onlyLauncher() {
        if (msg.sender != launcher) {
            revert();
        }
        _;
    }

    modifier onlyLauncherOrOriginalSetter() {
        if (msg.sender != launcher && msg.sender != originalIsCreationRestrictedSetter) {
            revert();
        }
        _;
    }

    constructor(address _launcher, address _originalIsCreationRestrictedSetter, address _factory) {
        launcher = _launcher;
        originalIsCreationRestrictedSetter = _originalIsCreationRestrictedSetter;
        factory = IButtonswapFactory(_factory);
    }

    // Only callable by the launcher
    function returnPermissions() external onlyLauncherOrOriginalSetter {
        factory.setIsCreationRestrictedSetter(originalIsCreationRestrictedSetter);
    }

    // Only callable by the launcher
    function enqueuePair(address tokenA, address tokenB, uint256 amountA, uint256 amountB) external onlyLauncher {
        pairStack.push(PairData(tokenA, tokenB, amountA, amountB));
    }

    function _createTopPair() internal {
        // Pop the top of the stack
        PairData memory pairData = pairStack[pairStack.length - 1];
        pairStack.pop();

        address pair = factory.createPair(pairData.tokenA, pairData.tokenB);
        address tokenA = pairData.tokenA;
        address tokenB = pairData.tokenB;
        uint256 amountA = pairData.amountA;
        uint256 amountB = pairData.amountB;

        TransferHelper.safeTransferFrom(tokenA, msg.sender, address(this), amountA);
        TransferHelper.safeApprove(tokenA, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, address(this), amountB);
        TransferHelper.safeApprove(tokenB, pair, amountB);

        if (tokenA < tokenB) {
            IButtonswapPair(pair).mint(amountA, amountB, launcher);
        } else {
            IButtonswapPair(pair).mint(amountB, amountA, launcher);
        }
    }

    function batchCreate5() external onlyLauncher {
        for (uint256 i = 0; i < 5; i++) {
            if (pairStack.length == 0) {
                return;
            }
            _createTopPair();
        }
    }

    function destroy() external onlyLauncherOrOriginalSetter {
        if (factory.isCreationRestrictedSetter() != originalIsCreationRestrictedSetter) {
            revert();
        }
        selfdestruct(payable(launcher));
    }
}
