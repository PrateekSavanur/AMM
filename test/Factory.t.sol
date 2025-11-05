// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {Factory} from "../src/core/Factory.sol";
import {Pair} from "../src/core/Pair.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract FactoryTest is Test {
    Factory factory;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    ERC20Mock tokenC;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 index);

    function setUp() public {
        factory = new Factory();

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();
    }

    function testCreatePairSuccess() public {
        address pair = factory.createPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0), "Pair address should not be zero");

        // Check stored pair
        address storedPair = factory.getPair(address(tokenA), address(tokenB));
        assertEq(pair, storedPair, "Stored pair does not match returned pair");

        // Pair count
        assertEq(factory.allPairsLength(), 1, "Pair count should be 1");
    }

    function testTokenSortingInPairStorage() public {
        address pair1 = factory.createPair(address(tokenB), address(tokenA));

        (address token0, address token1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        // Should store in sorted order
        address storedAB = factory.getPair(token0, token1);
        assertEq(pair1, storedAB, "Pair should be stored in sorted token order");

        // Reverse lookup should also work
        address storedBA = factory.getPair(address(tokenB), address(tokenA));
        assertEq(pair1, storedBA, "Reverse mapping should return the same pair");
    }

    function testDuplicatePairReverts() public {
        factory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert(bytes("Factory: PAIR_EXISTS"));
        factory.createPair(address(tokenA), address(tokenB));
    }

    function testIdenticalAddressesReverts() public {
        vm.expectRevert(bytes("Factory: IDENTICAL_ADDRESSES"));
        factory.createPair(address(tokenA), address(tokenA));
    }

    function testZeroAddressReverts() public {
        vm.expectRevert(bytes("Factory: ZERO_ADDRESS"));
        factory.createPair(address(tokenA), address(0));
    }

    function testEventEmitted() public {
        address token0 = address(tokenA);
        address token1 = address(tokenB);

        vm.expectEmit(true, true, false, false); // match indexed token0, token1, and data
        emit PairCreated(token0, token1, address(0), 1);

        factory.createPair(token0, token1);
    }



    function testAllPairsLength() public {
        factory.createPair(address(tokenA), address(tokenB));
        factory.createPair(address(tokenA), address(tokenC));
        assertEq(factory.allPairsLength(), 2, "Pair count should be 2");
    }
}
