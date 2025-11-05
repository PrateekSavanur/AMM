// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/core/Pair.sol";
import "../src/core/Factory.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PairTest is Test {
    Factory factory;
    Pair pair;
    ERC20Mock tokenA;
    ERC20Mock tokenB;
    address lpUser;

    function setUp() public {
        factory = new Factory();
        tokenA = new ERC20Mock();
        tokenB = new ERC20Mock();
        lpUser = makeAddr("LP_USER");

        // create pair via factory
        address pairAddr = factory.createPair(address(tokenA), address(tokenB));
        pair = Pair(pairAddr);

        // mint tokens to lpUser
        tokenA.mint(lpUser, 1_000 ether);
        tokenB.mint(lpUser, 1_000 ether);
    }

    function test_DeploymentAndInit() public view{
        assertEq(pair.factory(), address(factory));
        (address t0, address t1) = (pair.token0(), pair.token1());
        assertTrue(t0 != address(0) && t1 != address(0));
        assertTrue(t0 != t1);
    }

    function testMintLiquidity() public {
        vm.startPrank(lpUser);

        tokenA.transfer(address(pair), 100 ether);
        tokenB.transfer(address(pair), 100 ether);

        uint256 liquidity = pair.mint(lpUser);
        assertGt(liquidity, 0, "Liquidity should be minted");

        (uint112 r0, uint112 r1, ) = pair.getReserves();
        assertEq(r0, 100 ether);
        assertEq(r1, 100 ether);

        vm.stopPrank();
    }

    function testBurnLiquidity() public {
        vm.startPrank(lpUser);

        tokenA.transfer(address(pair), 100 ether);
        tokenB.transfer(address(pair), 100 ether);
        pair.mint(lpUser);

        // Transfer LP tokens to pair to burn
        uint256 lpBal = pair.balanceOf(lpUser);
        pair.transfer(address(pair), lpBal);

        (uint112 beforeR0, , ) = pair.getReserves();
        (uint256 amount0, uint256 amount1) = pair.burn(lpUser);

        (uint112 afterR0, , ) = pair.getReserves();
        assertGt(amount0, 0);
        assertGt(amount1, 0);
        assertLt(afterR0, beforeR0);

        vm.stopPrank();
    }

    function testSwap() public {
        vm.startPrank(lpUser);

        // provide initial liquidity
        tokenA.transfer(address(pair), 100 ether);
        tokenB.transfer(address(pair), 100 ether);
        pair.mint(lpUser);

        // swap: send in tokenA, expect some tokenB out
        tokenA.transfer(address(pair), 10 ether);
        pair.swap(0, 9 ether, lpUser); // tokenB out

        (uint112 r0, uint112 r1, ) = pair.getReserves();
        assertTrue(r0 > 100 ether, "reserve0 increased");
        assertTrue(r1 < 100 ether, "reserve1 decreased");

        vm.stopPrank();
    }

    function testSync() public {
        vm.startPrank(lpUser);
        tokenA.transfer(address(pair), 50 ether);
        tokenB.transfer(address(pair), 50 ether);
        pair.sync();
        (uint112 r0, uint112 r1, ) = pair.getReserves();
        assertEq(r0, 50 ether);
        assertEq(r1, 50 ether);
        vm.stopPrank();
    }

    function testTokenAddresses() public {
        assertEq(pair.token0(), address(tokenA));
        assertEq(pair.token1(), address(tokenB));
    }

}
