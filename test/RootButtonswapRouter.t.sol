// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "buttonswap-periphery_forge-std/Test.sol";
import {IButtonswapRouterErrors} from "../src/interfaces/IButtonswapRouter/IButtonswapRouterErrors.sol";
import {RootButtonswapRouter} from "../src/RootButtonswapRouter.sol";
import {ButtonswapFactory} from "buttonswap-periphery_buttonswap-core/ButtonswapFactory.sol";

contract RootButtonswapRouterTest is Test, IButtonswapRouterErrors {
    address public feeToSetter;
    uint256 public feeToSetterPrivateKey;
    address public isCreationRestrictedSetter;
    uint256 public isCreationRestrictedSetterPrivateKey;
    address public isPausedSetter;
    uint256 public isPausedSetterPrivateKey;
    address public paramSetter;
    uint256 public paramSetterPrivateKey;
    ButtonswapFactory public buttonswapFactory;
    RootButtonswapRouter public rootButtonswapRouter;

    function setUp() public {
        (feeToSetter, feeToSetterPrivateKey) = makeAddrAndKey("feeToSetter");
        (isCreationRestrictedSetter, isCreationRestrictedSetterPrivateKey) =
            makeAddrAndKey("isCreationRestrictedSetter");
        (isPausedSetter, isPausedSetterPrivateKey) = makeAddrAndKey("isPausedSetter");
        (paramSetter, paramSetterPrivateKey) = makeAddrAndKey("paramSetter");
        buttonswapFactory = new ButtonswapFactory(
            feeToSetter, isCreationRestrictedSetter, isPausedSetter, paramSetter, "LP Token", "LP"
        );
        rootButtonswapRouter = new RootButtonswapRouter(address(buttonswapFactory));
    }

    function test_factory() public view {
        assertEq(rootButtonswapRouter.factory(), address(buttonswapFactory));
    }

    function test_constructor() public view {
        assertEq(rootButtonswapRouter.factory(), address(buttonswapFactory));
    }
}
