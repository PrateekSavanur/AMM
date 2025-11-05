// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IFactory {
    event PairCreated(address token0, address token1, address pair, uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address);
}
