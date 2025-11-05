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
    using UniswapV2Library for address;

    address public immutable factory;
    address public immutable WETH;

    constructor(address _factory, address _WETH) {
        require(_factory != address(0) && _WETH != address(0), "Router: ZERO_ADDRESS");
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        // only accept ETH via WETH fallback
        require(msg.sender == WETH, "Router: ONLY_WETH");
    }

    // ----------------- INTERNAL HELPERS -----------------

    /// @notice Ensure pair exists; create if missing
    function _ensurePair(address tokenA, address tokenB) internal returns (address pair) {
        pair = Factory(factory).getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = Factory(factory).createPair(tokenA, tokenB);
        }
    }

    /// @notice Refund any leftover ETH to `to`
    function _refundETH(address to, uint256 amount) internal {
        if (amount > 0) {
            TransferHelper.safeTransferETH(to, amount);
        }
    }

    /// @notice Internal swap loop that performs multi-hop swaps.
    /// Splitting into an internal function reduces stack usage in public functions.
    function _swap(uint256[] memory amounts, address[] calldata path, address _to) internal {
        uint len = path.length;
        for (uint i = 0; i < len - 1; i++) {
            address input = path[i];
            address output = path[i + 1];
            address pair = UniswapV2Library.pairFor(factory, input, output);
            require(pair != address(0), "Router: PAIR_NOT_EXIST_IN_PATH");

            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];

            uint256 amount0Out;
            uint256 amount1Out;
            if (input == token0) {
                amount0Out = 0;
                amount1Out = amountOut;
            } else {
                amount0Out = amountOut;
                amount1Out = 0;
            }

            address recipient = (i < len - 2) ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            Pair(pair).swap(amount0Out, amount1Out, recipient);
        }
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

        address pair = _ensurePair(tokenA, tokenB);

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

        address pair = _ensurePair(token, WETH);

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

        // transfer token to pair
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);

        // wrap ETH and transfer WETH to pair
        IWETH(WETH).deposit{value: amountETH}();
        TransferHelper.safeTransfer(WETH, pair, amountETH);

        liquidity = Pair(pair).mint(to);

        // refund leftover ETH
        uint256 refund = msg.value - amountETH;
        if (refund > 0) _refundETH(msg.sender, refund);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        address pair = UniswapV2Library.pairFor(factory, tokenA, tokenB);
        require(pair != address(0), "Router: PAIR_NOT_EXIST");

        // pull LP to pair, then burn -> sends tokens to this contract
        TransferHelper.safeTransferFrom(pair, msg.sender, pair, liquidity);
        (uint256 out0, uint256 out1) = Pair(pair).burn(address(this));

        (address token0, ) = UniswapV2Library.sortTokens(tokenA, tokenB);
        if (tokenA == token0) {
            amountA = out0;
            amountB = out1;
        } else {
            amountA = out1;
            amountB = out0;
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
        address pair = UniswapV2Library.pairFor(factory, token, WETH);
        require(pair != address(0), "Router: PAIR_NOT_EXIST");

        TransferHelper.safeTransferFrom(pair, msg.sender, pair, liquidity);
        (uint256 out0, uint256 out1) = Pair(pair).burn(address(this));

        (address token0, ) = UniswapV2Library.sortTokens(token, WETH);
        if (token == token0) {
            amountToken = out0;
            amountETH = out1;
        } else {
            amountToken = out1;
            amountETH = out0;
        }

        TransferHelper.safeTransfer(token, to, amountToken);

        // unwrap & send ETH
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    // ----------------- SWAP (token-token and ETH wrappers, multi-hop) -----------------

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        address firstPair = UniswapV2Library.pairFor(factory, path[0], path[1]);
        require(firstPair != address(0), "Router: PAIR_NOT_EXIST");

        TransferHelper.safeTransferFrom(path[0], msg.sender, firstPair, amounts[0]);

        _swap(amounts, path, to);
    }

    // ETH -> multi-hop tokens (path[0] must be WETH)
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable nonReentrant returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(path.length >= 2, "Router: INVALID_PATH");
        require(path[0] == WETH, "Router: FIRST_TOKEN_MUST_BE_WETH");

        amounts = UniswapV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        // wrap ETH -> WETH and send to first pair
        IWETH(WETH).deposit{value: amounts[0]}();
        address firstPair = UniswapV2Library.pairFor(factory, path[0], path[1]);
        TransferHelper.safeTransfer(WETH, firstPair, amounts[0]);

        _swap(amounts, path, to);

        // refund leftover ETH, if any
        uint256 refund = msg.value - amounts[0];
        if (refund > 0) _refundETH(msg.sender, refund);
    }

    // Tokens -> ETH, multi-hop (last token in path must be WETH)
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

        amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "Router: INSUFFICIENT_OUTPUT_AMOUNT");

        // send input tokens to first pair
        address firstPair = UniswapV2Library.pairFor(factory, path[0], path[1]);
        TransferHelper.safeTransferFrom(path[0], msg.sender, firstPair, amounts[0]);

        // perform swaps, final recipient is this router so we can unwrap
        _swap(amounts, path, address(this));

        // unwrap final WETH to ETH and send to `to`
        uint256 amountWETH = amounts[amounts.length - 1];
        IWETH(WETH).withdraw(amountWETH);
        TransferHelper.safeTransferETH(to, amountWETH);
    }

        /// @notice Spend up to `amountInMax` of path[0] to receive exactly `amountOut` of the last token
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(path.length >= 2, "Router: INVALID_PATH");

        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "Router: EXCESSIVE_INPUT_AMOUNT");

        address firstPair = UniswapV2Library.pairFor(factory, path[0], path[1]);
        require(firstPair != address(0), "Router: PAIR_NOT_EXIST");

        // pull exact required input from user to first pair
        TransferHelper.safeTransferFrom(path[0], msg.sender, firstPair, amounts[0]);

        _swap(amounts, path, to);
    }

    /// @notice Spend up to `msg.value` ETH to receive exactly `amountOut` of the last token (path[0] must be WETH)
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable nonReentrant returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(path.length >= 2, "Router: INVALID_PATH");
        require(path[0] == WETH, "Router: FIRST_TOKEN_MUST_BE_WETH");

        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        uint256 requiredWETH = amounts[0];
        require(requiredWETH <= msg.value, "Router: INSUFFICIENT_ETH");

        // wrap required ETH and send to first pair
        IWETH(WETH).deposit{value: requiredWETH}();
        address firstPair = UniswapV2Library.pairFor(factory, path[0], path[1]);
        TransferHelper.safeTransfer(WETH, firstPair, requiredWETH);

        _swap(amounts, path, to);

        // refund leftover ETH to sender
        uint256 refund = msg.value - requiredWETH;
        if (refund > 0) _refundETH(msg.sender, refund);
    }

    /// @notice Spend up to `amountInMax` of path[0] to receive exactly `amountOut` ETH (last token must be WETH)
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external nonReentrant returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Router: EXPIRED");
        require(path.length >= 2, "Router: INVALID_PATH");
        require(path[path.length - 1] == WETH, "Router: LAST_TOKEN_MUST_BE_WETH");

        amounts = UniswapV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "Router: EXCESSIVE_INPUT_AMOUNT");

        address firstPair = UniswapV2Library.pairFor(factory, path[0], path[1]);
        require(firstPair != address(0), "Router: PAIR_NOT_EXIST");

        // pull required input tokens to first pair
        TransferHelper.safeTransferFrom(path[0], msg.sender, firstPair, amounts[0]);

        // perform swaps with final recipient being this router so we can unwrap
        _swap(amounts, path, address(this));

        // unwrap WETH to ETH and send to `to`
        uint256 amountWETH = amounts[amounts.length - 1];
        IWETH(WETH).withdraw(amountWETH);
        TransferHelper.safeTransferETH(to, amountWETH);
    }


    // ----------------- HELPERS / QUERIES -----------------

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        return UniswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory amounts) {
        return UniswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path) external view returns (uint256[] memory amounts) {
        return UniswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
