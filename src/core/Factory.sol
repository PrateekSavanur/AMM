// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../core/Pair.sol";

/// @title Minimal Factory for Uniswap V2 style AMM
/// @notice Permissionless factory that deploys Pair contracts and keeps registry
contract Factory {
    // tokenA => tokenB => pair address
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    /// @notice Create a pair for tokenA and tokenB
    /// @dev Anyone may call this. Tokens are sorted to avoid duplicates.
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, "Factory: IDENTICAL_ADDRESSES");
        require(tokenA != address(0) && tokenB != address(0), "Factory: ZERO_ADDRESS");

        // sort tokens
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        require(getPair[token0][token1] == address(0), "Factory: PAIR_EXISTS"); // single check is sufficient

        // deploy new Pair; Pair constructor sets factory = msg.sender (this contract)
        Pair newPair = new Pair();

        // initialize pair with tokens (only callable by factory)
        newPair.initialize(token0, token1);

        pair = address(newPair);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate reverse mapping for convenience
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /// @notice Returns number of pairs created
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
}
