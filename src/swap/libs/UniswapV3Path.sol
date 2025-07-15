// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

/**
 * @title  Uniswap V3 Path Library
 * @author Uniswap Labs
 *         Adapted from https://github.com/Uniswap/universal-router/blob/main/contracts/modules/uniswap/v3/V3Path.sol
 * @notice Provides functions to decode and manipulate Uniswap V3 path data.
 */
library UniswapV3Path {
    error InvalidPathFormat();

    /// @dev The length of the bytes encoded address
    uint256 internal constant ADDR_SIZE = 20;

    /// @dev The length of the bytes encoded fee
    uint256 internal constant V3_FEE_SIZE = 3;

    /// @dev The offset of a single token address (20) and pool fee (3)
    uint256 internal constant NEXT_V3_POOL_OFFSET = ADDR_SIZE + V3_FEE_SIZE;

    /// @dev The offset of an encoded pool key
    /// Token (20) + Fee (3) + Token (20) = 43
    uint256 internal constant V3_POP_OFFSET = NEXT_V3_POOL_OFFSET + ADDR_SIZE;

    /// @dev The minimum length of an encoding that contains 2 or more pools
    uint256 internal constant MULTIPLE_V3_POOLS_MIN_LENGTH = V3_POP_OFFSET + NEXT_V3_POOL_OFFSET;

    /**
     * @notice Checks whether the given `path` contains two or more pools
     * @param  path          The encoded swap path.
     * @return multiplePools True if the path contains two or more pools, otherwise false.
     */
    function hasMultiplePools(bytes calldata path) internal pure returns (bool multiplePools) {
        return path.length >= MULTIPLE_V3_POOLS_MIN_LENGTH;
    }

    /**
     * @notice Decodes the first pool in the given `path`.
     * @param  path   The bytes encoded swap path.
     * @return tokenA The first token of the given pool.
     * @return fee    The fee level of the pool.
     * @return tokenB The second token of the given pool.
     */
    function decodeFirstPool(bytes calldata path) internal pure returns (address tokenA, uint24 fee, address tokenB) {
        if (path.length < V3_POP_OFFSET) revert InvalidPathFormat();
        assembly {
            let firstWord := calldataload(path.offset)
            tokenA := shr(96, firstWord)
            fee := and(shr(72, firstWord), 0xffffff)
            tokenB := shr(96, calldataload(add(path.offset, 23)))
        }
    }

    /**
     * @notice Skips a token + fee element
     * @param path The swap path
     */
    function skipToken(bytes calldata path) internal pure returns (bytes calldata) {
        return path[NEXT_V3_POOL_OFFSET:];
    }
}
