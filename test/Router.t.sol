// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import {Factory} from "../src/core/Factory.sol";
import {Pair} from "../src/core/Pair.sol";
import {WETH} from "../src/periphery/WETH.sol";
import {Router} from "../src/periphery/Router.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract RouterTestFixed is Test {
    Factory factory;
    WETH weth;
    Router router;
    ERC20Mock tokenA;
    ERC20Mock tokenB;

    address alice;
    address bob;

    uint256 constant INITIAL = 1_000 ether;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        factory = new Factory();
        weth = new WETH();
        router = new Router(address(factory), address(weth));

        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();

        // Mint tokens to BOTH alice and bob
        tokenA.mint(alice, INITIAL);
        tokenB.mint(alice, INITIAL);
        tokenA.mint(bob, INITIAL);
        tokenB.mint(bob, INITIAL);
        
        // Give alice and bob some ETH for ETH-based tests
        vm.deal(alice, INITIAL);
        vm.deal(bob, INITIAL);
    }

    function _pairFor(address tokenX, address tokenY) internal view returns (Pair p, uint256 resX, uint256 resY) {
        address pairAddr = factory.getPair(tokenX, tokenY);
        p = Pair(pairAddr);
        (uint112 r0, uint112 r1, ) = p.getReserves();
        if (p.token0() == tokenX) {
            (resX, resY) = (uint256(r0), uint256(r1));
        } else {
            (resX, resY) = (uint256(r1), uint256(r0));
        }
    }

    function testAddLiquidityTokenToken() public {
        // Create the pair first
        factory.createPair(address(tokenA), address(tokenB));
        
        uint256 desiredA = 100 ether;
        uint256 desiredB = 200 ether;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(alice);
        tokenA.approve(address(router), desiredA);
        tokenB.approve(address(router), desiredB);

        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            router.addLiquidity(address(tokenA), address(tokenB), desiredA, desiredB, alice, deadline);
        vm.stopPrank();

        assertTrue(liquidity > 0);
        assertEq(amountA, desiredA);
        assertEq(amountB, desiredB);

        (Pair p, uint256 rA, uint256 rB) = _pairFor(address(tokenA), address(tokenB));
        assertEq(rA, amountA);
        assertEq(rB, amountB);

        uint256 lpBal = p.balanceOf(alice);
        assertTrue(lpBal > 0);
    }

    function testAddLiquidityETHAndSwapExactETHForTokens() public {
        // Create the pair first (tokenA-WETH)
        factory.createPair(address(tokenA), address(weth));
        
        uint256 amountTokenDesired = 500 ether;
        uint256 amountETH = 500 ether;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountTokenDesired);

        (uint256 amountToken, uint256 amountETHAdded, uint256 liquidity) =
            router.addLiquidityETH{value: amountETH}(address(tokenA), amountTokenDesired, alice, deadline);
        vm.stopPrank();

        assertEq(amountToken, amountTokenDesired);
        assertEq(amountETHAdded, amountETH);
        assertTrue(liquidity > 0);

        // Mine a new block to ensure reserves are updated
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(tokenA);

        uint256 swapETH = 0.1 ether;  // Reduced to avoid precision issues

        vm.prank(bob);
        router.swapExactETHForTokens{value: swapETH}(0, path, bob, deadline);

        uint256 bobToken = tokenA.balanceOf(bob);
        assertTrue(bobToken > 0);
    }

    function testSwapExactTokensForTokens() public {
        // Create the pair first
        factory.createPair(address(tokenA), address(tokenB));
        
        uint256 supplyA = 500 ether;
        uint256 supplyB = 500 ether;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(alice);
        tokenA.approve(address(router), supplyA);
        tokenB.approve(address(router), supplyB);

        router.addLiquidity(address(tokenA), address(tokenB), supplyA, supplyB, alice, deadline);
        vm.stopPrank();

        // Mine a new block to ensure reserves are updated
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        uint256 amountIn = 1 ether;  // Reduced to avoid precision issues
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.startPrank(bob);
        tokenA.approve(address(router), amountIn);

        router.swapExactTokensForTokens(amountIn, 0, path, bob, deadline);
        vm.stopPrank();

        uint256 bobReceived = tokenB.balanceOf(bob);
        assertTrue(bobReceived > 0);
    }

    function testRemoveLiquidityTokenToken() public {
        // Create the pair first
        factory.createPair(address(tokenA), address(tokenB));
        
        uint256 amountA = 100 ether;
        uint256 amountB = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(alice);
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        (, , uint256 liquidity) = router.addLiquidity(address(tokenA), address(tokenB), amountA, amountB, alice, deadline);
        vm.stopPrank();

        address pairAddr = factory.getPair(address(tokenA), address(tokenB));
        Pair p = Pair(pairAddr);
        
        // Need to remove the MINIMUM_LIQUIDITY that gets locked
        uint256 MINIMUM_LIQUIDITY = 1000;
        uint256 removableLiquidity = liquidity - MINIMUM_LIQUIDITY;

        vm.startPrank(alice);
        p.approve(address(router), removableLiquidity);

        (uint256 outA, uint256 outB) = router.removeLiquidity(
            address(tokenA), 
            address(tokenB), 
            removableLiquidity, 
            alice, 
            deadline
        );
        vm.stopPrank();

        assertTrue(outA > 0 && outB > 0);
        
        // Check balances considering the locked liquidity
        uint256 aliceBalanceA = tokenA.balanceOf(alice);
        uint256 aliceBalanceB = tokenB.balanceOf(alice);
        
        assertTrue(aliceBalanceA > INITIAL - amountA);
        assertTrue(aliceBalanceB > INITIAL - amountB);
        assertTrue(aliceBalanceA < INITIAL);
        assertTrue(aliceBalanceB < INITIAL);
    }
}