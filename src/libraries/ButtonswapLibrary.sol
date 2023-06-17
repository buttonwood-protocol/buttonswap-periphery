pragma solidity ^0.8.13;

import {IButtonswapPair} from "buttonswap-periphery_buttonswap-core/interfaces/IButtonswapPair/IButtonswapPair.sol";
import {Math} from "buttonswap-periphery_buttonswap-core/libraries/Math.sol";
import {IERC20} from "../interfaces/IERC20.sol";

library ButtonswapLibrary {
    /// @notice Identical addresses provided
    error IdenticalAddresses();
    /// @notice Zero address provided
    error ZeroAddress();
    /// @notice Insufficient amount provided
    error InsufficientAmount();
    /// @notice Insufficient liquidity provided
    error InsufficientLiquidity();
    /// @notice Insufficient input amount provided
    error InsufficientInputAmount();
    /// @notice Insufficient output amount provided
    error InsufficientOutputAmount();
    /// @notice Invalid path provided
    error InvalidPath();

    /**
     * @dev Returns sorted token addresses, used to handle return values from pairs sorted in this order
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return token0 First sorted token address
     * @return token1 Second sorted token address
     */
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) {
            revert IdenticalAddresses();
        }
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // If the tokens are different and sorted, only token0 can be the zero address
        if (token0 == address(0)) {
            revert ZeroAddress();
        }
    }

    /**
     * @dev Predicts the address that the Pair contract for given tokens would have been deployed to
     * @dev Specifically, this calculates the CREATE2 address for a Pair contract.
     * @dev It's done this way to avoid making any external calls, and thus saving on gas versus other approaches.
     * @param factory The address of the ButtonswapFactory used to create the pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pair The pair address
     */
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        // Init Hash Code is generated by the following command:
        //        bytes32 initHashCode = keccak256(abi.encodePacked(type(ButtonswapPair).creationCode));
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"6e811b82ea57b56cd99db0f6fe185df0dd2c164a9e965af24fd7c6d6e57cee0f" // init code hash
                        )
                    )
                )
            )
        );
    }

    /**
     * @dev Fetches and sorts the pools for a pair. Pools are the current token balances in the pair contract serving as liquidity.
     * @param factory The address of the ButtonswapFactory
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return poolA Pool corresponding to tokenA
     * @return poolB Pool corresponding to tokenB
     */
    function getPools(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 poolA, uint256 poolB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 pool0, uint256 pool1,,,) = IButtonswapPair(pairFor(factory, tokenA, tokenB)).getLiquidityBalances();
        (poolA, poolB) = tokenA == token0 ? (pool0, pool1) : (pool1, pool0);
    }

    /**
     * @dev Fetches and sorts the reservoirs for a pair. Reservoirs are the current token balances in the pair contract not actively serving as liquidity.
     * @param factory The address of the ButtonswapFactory
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return reservoirA Reservoir corresponding to tokenA
     * @return reservoirB Reservoir corresponding to tokenB
     */
    function getReservoirs(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reservoirA, uint256 reservoirB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (,, uint256 reservoir0, uint256 reservoir1,) =
            IButtonswapPair(pairFor(factory, tokenA, tokenB)).getLiquidityBalances();
        (reservoirA, reservoirB) = tokenA == token0 ? (reservoir0, reservoir1) : (reservoir1, reservoir0);
    }

    /**
     * @dev Fetches and sorts the pools and reservoirs for a pair.
     *   - Pools are the current token balances in the pair contract serving as liquidity.
     *   - Reservoirs are the current token balances in the pair contract not actively serving as liquidity.
     * @param factory The address of the ButtonswapFactory
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return poolA Pool corresponding to tokenA
     * @return poolB Pool corresponding to tokenB
     * @return reservoirA Reservoir corresponding to tokenA
     * @return reservoirB Reservoir corresponding to tokenB
     */
    function getLiquidityBalances(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 poolA, uint256 poolB, uint256 reservoirA, uint256 reservoirB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 pool0, uint256 pool1, uint256 reservoir0, uint256 reservoir1,) =
            IButtonswapPair(pairFor(factory, tokenA, tokenB)).getLiquidityBalances();
        (poolA, poolB, reservoirA, reservoirB) =
            tokenA == token0 ? (pool0, pool1, reservoir0, reservoir1) : (pool1, pool0, reservoir1, reservoir0);
    }

    /**
     * @dev Given some amount of an asset and pair pools, returns an equivalent amount of the other asset
     * @param amountA The amount of token A
     * @param poolA The balance of token A in the pool
     * @param poolB The balance of token B in the pool
     * @return amountB The amount of token B
     */
    function quote(uint256 amountA, uint256 poolA, uint256 poolB) internal pure returns (uint256 amountB) {
        if (amountA == 0) {
            revert InsufficientAmount();
        }
        if (poolA == 0 || poolB == 0) {
            revert InsufficientLiquidity();
        }
        amountB = (amountA * poolB) / poolA;
    }

    /**
     * @dev Given a factory, two tokens, and a mintAmount of the first, returns how much of the much of the mintAmount will be swapped for the other token and for how much during a mintWithReservoir operation.
     * @dev The logic is a condensed version of PairMath.getSingleSidedMintLiquidityOutAmountA and PairMath.getSingleSidedMintLiquidityOutAmountB
     * @param factory The address of the ButtonswapFactory that created the pairs
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param mintAmountA The amount of tokenA to be minted
     * @return tokenAToSwap The amount of tokenA to be exchanged for tokenB from the reservoir
     * @return swappedReservoirAmountB The amount of tokenB returned from the reservoir
     */
    function getMintSwappedAmounts(address factory, address tokenA, address tokenB, uint256 mintAmountA)
        internal
        view
        returns (uint256 tokenAToSwap, uint256 swappedReservoirAmountB)
    {
        IButtonswapPair pair = IButtonswapPair(pairFor(factory, tokenA, tokenB));
        uint256 totalA = IERC20(tokenA).balanceOf(address(pair));
        uint256 totalB = IERC20(tokenB).balanceOf(address(pair));
        uint256 movingAveragePrice0 = pair.movingAveragePrice0();

        // tokenA == token0
        if (tokenA < tokenB) {
            tokenAToSwap =
                (mintAmountA * totalB) / (Math.mulDiv(movingAveragePrice0, (totalA + mintAmountA), 2 ** 112) + totalB);
            swappedReservoirAmountB = (tokenAToSwap * movingAveragePrice0) / 2 ** 112;
        } else {
            tokenAToSwap =
                (mintAmountA * totalB) / (((2 ** 112 * (totalA + mintAmountA)) / movingAveragePrice0) + totalB);
            // Inverse price so again we can use it without overflow risk
            swappedReservoirAmountB = (tokenAToSwap * (2 ** 112)) / movingAveragePrice0;
        }
    }

    /**
     * @dev Given a factory, two tokens, and a liquidity amount, returns how much of the first token will be withdrawn from the pair and how much of it came from the reservoir during a burnFromReservoir operation.
     * @dev The logic is a condensed version of PairMath.getSingleSidedBurnOutputAmountA and PairMath.getSingleSidedBurnOutputAmountB
     * @param factory The address of the ButtonswapFactory that created the pairs
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param liquidity The amount of liquidity to be burned
     * @return tokenOutA The amount of tokenA to be withdrawn from the pair
     * @return swappedReservoirAmountA The amount of tokenA returned from the reservoir
     */
    function getBurnSwappedAmounts(address factory, address tokenA, address tokenB, uint256 liquidity)
        internal
        view
        returns (uint256 tokenOutA, uint256 swappedReservoirAmountA)
    {
        IButtonswapPair pair = IButtonswapPair(pairFor(factory, tokenA, tokenB));
        uint256 totalLiquidity = pair.totalSupply();
        uint256 totalA = IERC20(tokenA).balanceOf(address(pair));
        uint256 totalB = IERC20(tokenB).balanceOf(address(pair));
        uint256 movingAveragePrice0 = pair.movingAveragePrice0();
        uint256 tokenBToSwap = (totalB * liquidity) / totalLiquidity;
        tokenOutA = (totalA * liquidity) / totalLiquidity;

        // tokenA == token0
        if (tokenA < tokenB) {
            swappedReservoirAmountA = (tokenBToSwap * (2 ** 112)) / movingAveragePrice0;
        } else {
            swappedReservoirAmountA = (tokenBToSwap * movingAveragePrice0) / 2 ** 112;
        }
        tokenOutA += swappedReservoirAmountA;
    }

    /**
     * @dev Given an input amount of an asset and pair pools, returns the maximum output amount of the other asset
     * Factors in the fee on the input amount.
     * @param amountIn The input amount of the asset
     * @param poolIn The balance of the input asset in the pool
     * @param poolOut The balance of the output asset in the pool
     * @return amountOut The output amount of the other asset
     */
    function getAmountOut(uint256 amountIn, uint256 poolIn, uint256 poolOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) {
            revert InsufficientInputAmount();
        }
        if (poolIn == 0 || poolOut == 0) {
            revert InsufficientLiquidity();
        }
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * poolOut;
        uint256 denominator = (poolIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @dev Given an output amount of an asset and pair pools, returns a required input amount of the other asset
     * @param amountOut The output amount of the asset
     * @param poolIn The balance of the input asset in the pool
     * @param poolOut The balance of the output asset in the pool
     * @return amountIn The required input amount of the other asset
     */
    function getAmountIn(uint256 amountOut, uint256 poolIn, uint256 poolOut) internal pure returns (uint256 amountIn) {
        if (amountOut == 0) {
            revert InsufficientOutputAmount();
        }
        if (poolIn == 0 || poolOut == 0) {
            revert InsufficientLiquidity();
        }
        uint256 numerator = poolIn * amountOut * 1000;
        uint256 denominator = (poolOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /**
     * @dev Given an ordered array of tokens and an input amount of the first asset, performs chained getAmountOut calculations to calculate the output amount of the final asset
     * @param factory The address of the ButtonswapFactory that created the pairs
     * @param amountIn The input amount of the first asset
     * @param path An array of token addresses [tokenA, tokenB, tokenC, ...] representing the path the input token takes to get to the output token
     * @return amounts The output amounts of each asset in the path
     */
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) {
            revert InvalidPath();
        }
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 poolIn, uint256 poolOut,,) = getLiquidityBalances(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], poolIn, poolOut);
        }
    }

    /**
     * @dev Given an ordered array of tokens and an output amount of the final asset, performs chained getAmountIn calculations to calculate the input amount of the first asset
     * @param factory The address of the ButtonswapFactory that created the pairs
     * @param amountOut The output amount of the final asset
     * @param path An array of token addresses [tokenA, tokenB, tokenC, ...] representing the path the input token takes to get to the output token
     * @return amounts The input amounts of each asset in the path
     */
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) {
            revert InvalidPath();
        }
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 poolIn, uint256 poolOut,,) = getLiquidityBalances(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], poolIn, poolOut);
        }
    }
}
