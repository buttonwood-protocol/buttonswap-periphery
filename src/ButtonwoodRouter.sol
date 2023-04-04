// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IButtonswapFactory} from "buttonswap-core/interfaces/IButtonswapFactory/IButtonswapFactory.sol";
import {IButtonswapPair} from "buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {IButtonwoodRouter} from "./interfaces/IButtonwoodRouter/IButtonwoodRouter.sol";
import {ButtonswapLibrary} from "./libraries/ButtonswapLibrary.sol";
import {SafeMath} from "./libraries/SafeMath.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";

contract ButtonwoodRouter is IButtonwoodRouter {
    using SafeMath for uint256;

    /**
     * @inheritdoc IButtonwoodRouter
     */
    address public immutable override factory;
    /**
     * @inheritdoc IButtonwoodRouter
     */
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) {
            revert Expired();
        }
        _;
    }

    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    /**
     * @dev Only accepts ETH via fallback from the WETH contract
     */
    receive() external payable {
        assert(msg.sender == WETH);
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IButtonswapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IButtonswapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 poolA, uint256 poolB) = ButtonswapLibrary.getPools(factory, tokenA, tokenB);
        if (poolA == 0 && poolB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = ButtonswapLibrary.quote(amountADesired, poolA, poolB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) {
                    revert InsufficientBAmount();
                }
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = ButtonswapLibrary.quote(amountBDesired, poolB, poolA);
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) {
                    revert InsufficientAAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _addLiquidityWithReservoir(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // If the pair doesn't exist yet, there isn't any reservoir
        if (IButtonswapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            revert NoReservoir();
        }
        (uint256 poolA, uint256 poolB) = ButtonswapLibrary.getPools(factory, tokenA, tokenB);
        // the first liquidity addition should happen through _addLiquidity
        // can't initialize by matching with a reservoir
        if (poolA == 0 || poolB == 0) {
            revert NotInitialized();
        }
        (uint256 reservoirA, uint256 reservoirB) = ButtonswapLibrary.getReservoirs(factory, tokenA, tokenB);
        if (reservoirA == 0 && reservoirB == 0) {
            revert NoReservoir();
        }

        if (reservoirA > 0) {
            // we take from reservoirA and the user-provided amountBDesired
            uint256 amountAOptimal = ButtonswapLibrary.quote(amountBDesired, poolB, poolA);
            if (amountAOptimal < amountAMin) {
                revert InsufficientAAmount();
            }
            if (reservoirA < amountAOptimal) {
                revert InsufficientAReservoir();
            }
            (amountA, amountB) = (0, amountBDesired);
        } else {
            // we take from reservoirB and the user-provided amountADesired
            uint256 amountBOptimal = ButtonswapLibrary.quote(amountADesired, poolA, poolB);
            if (amountBOptimal < amountBMin) {
                revert InsufficientBAmount();
            }
            if (reservoirB < amountBOptimal) {
                revert InsufficientBReservoir();
            }
            (amountA, amountB) = (amountADesired, 0);
        }
    }

    /**
     * @inheritdoc IButtonwoodRouter
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = ButtonswapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IButtonswapPair(pair).mint(to);
    }

    /**
     * @inheritdoc IButtonwoodRouter
     */
    function addLiquidityWithReservoir(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) =
            _addLiquidityWithReservoir(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = ButtonswapLibrary.pairFor(factory, tokenA, tokenB);
        if (amountA > 0) {
            TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        } else if (amountB > 0) {
            TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        }

        liquidity = IButtonswapPair(pair).mintWithReservoir(to);
    }

    /**
     * @inheritdoc IButtonwoodRouter
     */
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        (amountToken, amountETH) =
            _addLiquidity(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address pair = ButtonswapLibrary.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IButtonswapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    /**
     * @inheritdoc IButtonwoodRouter
     */
    function addLiquidityETHWithReservoir(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        (amountToken, amountETH) =
            _addLiquidityWithReservoir(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address pair = ButtonswapLibrary.pairFor(factory, token, WETH);
        if (amountToken > 0) {
            TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        } else if (amountETH > 0) {
            IWETH(WETH).deposit{value: amountETH}();
            assert(IWETH(WETH).transfer(pair, amountETH));
        }
        liquidity = IButtonswapPair(pair).mintWithReservoir(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    /**
     * @inheritdoc IButtonwoodRouter
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = ButtonswapLibrary.pairFor(factory, tokenA, tokenB);
        IButtonswapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IButtonswapPair(pair).burn(to);
        (address token0,) = ButtonswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        if (amountA < amountAMin) {
            revert InsufficientAAmount();
        }
        if (amountB < amountBMin) {
            revert InsufficientBAmount();
        }
    }

    /**
     * @inheritdoc IButtonwoodRouter
     */
    function removeLiquidityFromReservoir(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = ButtonswapLibrary.pairFor(factory, tokenA, tokenB);
        IButtonswapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IButtonswapPair(pair).burnFromReservoir(to);
        (address token0,) = ButtonswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        if (amountA < amountAMin) {
            revert InsufficientAAmount();
        }
        if (amountB < amountBMin) {
            revert InsufficientBAmount();
        }
    }

    /**
     * @inheritdoc IButtonwoodRouter
     */
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) =
            removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHFromReservoir(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) =
            removeLiquidityFromReservoir(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        if (amountToken > 0) {
            TransferHelper.safeTransfer(token, to, amountToken);
        } else if (amountETH > 0) {
            IWETH(WETH).withdraw(amountETH);
            TransferHelper.safeTransferETH(to, amountETH);
        }
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pair = ButtonswapLibrary.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IButtonswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountETH) {
        address pair = ButtonswapLibrary.pairFor(factory, token, WETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IButtonswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountETH) {
        address pair = ButtonswapLibrary.pairFor(factory, token, WETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IButtonswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = ButtonswapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? ButtonswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IButtonswapPair(ButtonswapLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = ButtonswapLibrary.getAmountsOut(factory, amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, path[0], path[1]));
        pair.sync();

        TransferHelper.safeTransferFrom(path[0], msg.sender, address(pair), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = ButtonswapLibrary.getAmountsIn(factory, amountOut, path);
        if (amounts[0] > amountInMax) {
            revert ExcessiveInputAmount();
        }
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, path[0], path[1]));
        pair.sync();

        TransferHelper.safeTransferFrom(path[0], msg.sender, address(pair), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[0] != WETH) {
            revert InvalidPath();
        }
        amounts = ButtonswapLibrary.getAmountsOut(factory, msg.value, path);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, path[0], path[1]));
        pair.sync();

        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(address(pair), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WETH) {
            revert InvalidPath();
        }
        amounts = ButtonswapLibrary.getAmountsIn(factory, amountOut, path);
        if (amounts[0] > amountInMax) {
            revert ExcessiveInputAmount();
        }
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, path[0], path[1]));
        pair.sync();

        TransferHelper.safeTransferFrom(path[0], msg.sender, address(pair), amounts[0]);
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WETH) {
            revert InvalidPath();
        }
        amounts = ButtonswapLibrary.getAmountsOut(factory, amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, path[0], path[1]));
        pair.sync();

        TransferHelper.safeTransferFrom(path[0], msg.sender, address(pair), amounts[0]);
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[0] != WETH) {
            revert InvalidPath();
        }
        amounts = ButtonswapLibrary.getAmountsIn(factory, amountOut, path);
        if (amounts[0] > msg.value) {
            revert ExcessiveInputAmount();
        }
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, path[0], path[1]));
        pair.sync();

        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(address(pair), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // Return the input token's pool, output token's pool, and input token's reservoir
    function _getSortedPoolsAndReservoirs(IButtonswapPair pair, bool inputIsFirst)
        internal
        view
        returns (uint256 poolInput, uint256 poolOutput, uint256 reservoirInput)
    {
        (uint256 pool0, uint256 pool1,) = pair.getPools();
        (uint256 reservoir0, uint256 reservoir1) = pair.getReservoirs();
        return inputIsFirst ? (pool0, pool1, reservoir0) : (pool1, pool0, reservoir1);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = ButtonswapLibrary.sortTokens(input, output);
            IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, input, output));

            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 poolInput, uint256 poolOutput, uint256 reservoirInput) =
                    _getSortedPoolsAndReservoirs(pair, input == token0);

                amountInput = IERC20(input).balanceOf(address(pair)).sub(poolInput).sub(reservoirInput);
                amountOutput = ButtonswapLibrary.getAmountOut(amountInput, poolInput, poolOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? ButtonswapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, path[0], path[1]));
        pair.sync();
        TransferHelper.safeTransferFrom(path[0], msg.sender, address(pair), amountIn);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) < amountOutMin) {
            revert InsufficientOutputAmount();
        }
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) {
        if (path[0] != WETH) {
            revert InvalidPath();
        }
        uint256 amountIn = msg.value;
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, path[0], path[1]));
        pair.sync();

        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(address(pair), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (IERC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) < amountOutMin) {
            revert InsufficientOutputAmount();
        }
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        if (path[path.length - 1] != WETH) {
            revert InvalidPath();
        }
        IButtonswapPair pair = IButtonswapPair(ButtonswapLibrary.pairFor(factory, path[0], path[1]));
        pair.sync();

        TransferHelper.safeTransferFrom(path[0], msg.sender, address(pair), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        if (amountOut < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
        public
        pure
        virtual
        override
        returns (uint256 amountB)
    {
        return ButtonswapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountOut)
    {
        return ButtonswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountIn)
    {
        return ButtonswapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return ButtonswapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return ButtonswapLibrary.getAmountsIn(factory, amountOut, path);
    }
}
