// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../core/Factory.sol";
import "../core/Pair.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/UniswapV2Library.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
}

contract Router is ReentrancyGuard {
    address public immutable factory;
    address public immutable WETH;

    constructor(address _factory, address _WETH) {
        require(_factory != address(0) && _WETH != address(0), "Router: ZERO_ADDRESS");
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        require(msg.sender == WETH, "Router: ONLY_WETH");
    }

    // ----------------- ADD / REMOVE LIQUIDITY -----------------

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(to != address(0), "Router: INVALID_TO");

        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        require(pair != address(0), "Router: PAIR_NOT_EXIST");

        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = UniswapV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = UniswapV2Library.quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal <= amountADesired, "Router: INSUFFICIENT_A");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }

        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);

        liquidity = Pair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        address to,
        uint256 deadline
    ) external payable nonReentrant returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(to != address(0), "Router: INVALID_TO");

        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        require(pair != address(0), "Router: PAIR_NOT_EXIST");

        (uint256 reserveToken, uint256 reserveETH) = UniswapV2Library.getReserves(factory, token, WETH);
        if (reserveToken == 0 && reserveETH == 0) {
            (amountToken, amountETH) = (amountTokenDesired, msg.value);
        } else {
            uint256 amountETHOptimal = UniswapV2Library.quote(amountTokenDesired, reserveToken, reserveETH);
            if (amountETHOptimal <= msg.value) {
                (amountToken, amountETH) = (amountTokenDesired, amountETHOptimal);
            } else {
                uint256 amountTokenOptimal = UniswapV2Library.quote(msg.value, reserveETH, reserveToken);
                require(amountTokenOptimal <= amountTokenDesired, "Router: INSUFFICIENT_TOKEN_AMOUNT");
                (amountToken, amountETH) = (amountTokenOptimal, msg.value);
            }
        }

        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);

        IWETH(WETH).deposit{value: amountETH}();
        TransferHelper.safeTransfer(WETH, pair, amountETH);

        liquidity = Pair(pair).mint(to);

        uint256 refund = msg.value - amountETH;
        if (refund > 0) TransferHelper.safeTransferETH(msg.sender, refund);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(to != address(0), "Router: INVALID_TO");

        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        require(pair != address(0), "Router: PAIR_NOT_EXIST");

        TransferHelper.safeTransferFrom(pair, msg.sender, pair, liquidity);

        (uint256 out0, uint256 out1) = Pair(pair).burn(address(this));

        (address token0, ) = UniswapV2Library.sortTokens(tokenA, tokenB);
        if (tokenA == token0) {
            (amountA, amountB) = (out0, out1);
        } else {
            (amountA, amountB) = (out1, out0);
        }

        TransferHelper.safeTransfer(tokenA, to, amountA);
        TransferHelper.safeTransfer(tokenB, to, amountB);
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountToken, uint256 amountETH) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(to != address(0), "Router: INVALID_TO");

        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        require(pair != address(0), "Router: PAIR_NOT_EXIST");

        TransferHelper.safeTransferFrom(pair, msg.sender, pair, liquidity);
        (uint256 out0, uint256 out1) = Pair(pair).burn(address(this));

        (address token0, ) = UniswapV2Library.sortTokens(token, WETH);
        if (token == token0) {
            (amountToken, amountETH) = (out0, out1);
        } else {
            (amountToken, amountETH) = (out1, out0);
        }

        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // ----------------- SWAP FUNCTIONS -----------------

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(path.length >= 2, "Router: INVALID_PATH");
        require(to != address(0), "Router: INVALID_TO");

        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        address firstPair = UniswapV2Library.pairFor(factory, path[0], path[1]);
        require(firstPair != address(0), "Router: PAIR_NOT_EXIST");

        TransferHelper.safeTransferFrom(path[0], msg.sender, firstPair, amounts[0]);

        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable nonReentrant returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(path.length >= 2, "Router: INVALID_PATH");
        require(path[0] == WETH, "Router: FIRST_TOKEN_MUST_BE_WETH");
        require(to != address(0), "Router: INVALID_TO");

        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        IWETH(WETH).deposit{value: amounts[0]}();
        address firstPair = UniswapV2Library.pairFor(factory, path[0], path[1]);
        require(firstPair != address(0), "Router: FIRST_PAIR_MISSING");

        TransferHelper.safeTransfer(WETH, firstPair, amounts[0]);

        _swap(amounts, path, to);

        uint256 refund = msg.value - amounts[0];
        if (refund > 0) TransferHelper.safeTransferETH(msg.sender, refund);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(path.length >= 2, "Router: INVALID_PATH");
        require(path[path.length - 1] == WETH, "Router: LAST_TOKEN_MUST_BE_WETH");
        require(to != address(0), "Router: INVALID_TO");

        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        address firstPair = UniswapV2Library.pairFor(factory, path[0], path[1]);
        require(firstPair != address(0), "Router: PAIR_NOT_EXIST");

        TransferHelper.safeTransferFrom(path[0], msg.sender, firstPair, amounts[0]);

        _swap(amounts, path, address(this));

        uint256 amountWETH = amounts[amounts.length - 1];
        IWETH(WETH).withdraw(amountWETH);
        TransferHelper.safeTransferETH(to, amountWETH);
    }

    // ---------- INTERNAL SWAP ----------
    function _swap(uint256[] memory amounts, address[] calldata path, address _to) internal {
        uint len = path.length;
        for (uint i = 0; i < len - 1; i++) {
            address input = path[i];
            address output = path[i + 1];

            address pair = UniswapV2Library.pairFor(factory, input, output);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);

            uint256 amountOut = amounts[i + 1];
            uint256 amount0Out = input == token0 ? 0 : amountOut;
            uint256 amount1Out = input == token0 ? amountOut : 0;

            address recipient = i < len - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;

            Pair(pair).swap(amount0Out, amount1Out, recipient);
        }
    }

    // Add these at the end of Router.sol
    function getAmountsOut(uint256 amountIn, address[] calldata path) public view returns (uint256[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path) public view returns (uint256[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
