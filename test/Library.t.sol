// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {Pair} from "../src/core/Pair.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PairTest is Test {
    Pair pair;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    ERC20Mock tokenC;

    // helper addresses
    address alice = address(0xA11CE);
    address bob   = address(0xB0B);

    function setUp() public {
        // deploy pair FROM this test contract so this contract is the factory (Pair constructor sets factory = msg.sender)
        pair = new Pair();

        // deploy ERC20 mocks
        // Using the same pattern as in previous tests (ERC20Mock default constructor)
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        tokenC = new ERC20Mock();

        // sanity: pair not initialized yet
        (uint112 r0, uint112 r1, uint32 t) = pair.getReserves();
        assertEq(uint256(r0), 0);
        assertEq(uint256(r1), 0);
        assertEq(uint256(t), 0);
    }

    // ----------- INITIALIZATION TESTS -----------

    function test_initialize_onlyFactory_canCall() public {
        // since test contract deployed the pair, this contract is the factory and can call initialize
        pair.initialize(address(tokenA), address(tokenB));

        // token ordering should be sorted inside pair
        (address expected0, address expected1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        assertEq(pair.token0(), expected0, "token0 mismatch after initialize");
        assertEq(pair.token1(), expected1, "token1 mismatch after initialize");
    }

    function test_initialize_reverts_whenCalledByNonFactory() public {
        // deploy another Pair instance from a different address to simulate that case
        // We'll deploy a fresh pair from address `alice` using vm.prank to control msg.sender during construction.
        vm.prank(alice);
        Pair p2 = new Pair();

        // now try to call initialize from a non-factory address (bob) -> should revert with FORBIDDEN
        vm.prank(bob);
        vm.expectRevert(bytes("Pair: FORBIDDEN"));
        p2.initialize(address(tokenA), address(tokenB));
    }

    function test_initialize_reverts_ifAlreadyInitialized() public {
        // this contract is factory so it can initialize
        pair.initialize(address(tokenA), address(tokenB));

        // second initialize should revert with ALREADY_INITIALIZED
        vm.expectRevert(bytes("Pair: ALREADY_INITIALIZED"));
        pair.initialize(address(tokenA), address(tokenB));
    }

    function test_initialize_sortsTokensCorrectly() public {
        // call initialize with reversed order
        pair.initialize(address(tokenB), address(tokenA));

        (address expected0, address expected1) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        assertEq(pair.token0(), expected0, "token0 not sorted correctly");
        assertEq(pair.token1(), expected1, "token1 not sorted correctly");
    }

    function test_getReserves_initiallyZero() public view {
        // before initialization and liquidity, reserves should be zero
        (uint112 _r0, uint112 _r1, uint32 _t) = pair.getReserves();
        assertEq(uint256(_r0), 0, "reserve0 should be zero at deploy");
        assertEq(uint256(_r1), 0, "reserve1 should be zero at deploy");
        assertEq(uint256(_t), 0, "timestamp should be zero at deploy");
    }

    // ----------- Router-like helper for future tests -----------
    // This helper simulates what a Router would do: transfer tokens to pair then call mint()
    // Usage: call ensureInitialized() first in tests that need pair.token0/token1 set.

    function ensureInitialized() internal {
        // initialize only once
        // if token0 is zero, initialize
        if (pair.token0() == address(0) && pair.token1() == address(0)) {
            pair.initialize(address(tokenA), address(tokenB));
        }
    }

    /// @notice helper to simulate router adding liquidity: mint tokens to `from`, transfer to pair, then call mint()
    function _simulateAddLiquidity(address from, uint256 amountA, uint256 amountB) internal returns (uint256 liquidity) {
        ensureInitialized();

        // mint tokens to `from` and approve (ERC20Mock in many setups doesn't require approve for transfers from)
        tokenA.mint(from, amountA);
        tokenB.mint(from, amountB);

        // transfer tokens from `from` to pair
        vm.prank(from);
        tokenA.transfer(address(pair), amountA);

        vm.prank(from);
        tokenB.transfer(address(pair), amountB);

        // call mint from caller (router would call mint on pair)
        // we call mint from this test contract (router-like actor); no need to transfer LP beforehand
        liquidity = pair.mint(from);
    }
}
