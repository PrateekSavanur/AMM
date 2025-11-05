// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Math Library for AMM Calculations
/// @notice Provides sqrt and min functions used in Uniswap-like AMMs
library Math {
    /// @notice Returns the smaller of two numbers
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    /// @notice Calculates square root (Babylonian method)
    /// @dev Used to compute initial LP tokens: sqrt(x * y)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
        // else z = 0 (default)
    }
}
   
   