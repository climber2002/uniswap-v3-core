// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Math library for liquidity
library LiquidityMath {
    /// @notice Add a signed liquidity delta to liquidity and revert if it overflows or underflows
    /// @param x The liquidity before change
    /// @param y The delta by which liquidity should be changed
    /// @return z The liquidity delta
    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
        if (y < 0) {
            // For negative y, subtract: z = x - |y|
            // Need to convert: int128 → int256 → negate → uint256 → uint128
            z = x - uint128(uint256(-int256(y)));
            require(z < x, 'LS');
        } else {
            // For positive y, add: z = x + y
            // Need to convert: int128 → int256 → uint256 → uint128
            z = x + uint128(uint256(int256(y)));
            require(z >= x, 'LA');
        }
    }
}
