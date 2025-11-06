// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../libraries/Math.sol";

/// @title Pair (Uniswap V2 style) — the Pair contract is the LP token (ERC20)
/// @notice Each Pair contract holds two tokens, allows mint/burn/swaps and mints LP (UNI-V2)
contract Pair is ERC20, ReentrancyGuard {
    using Math for uint256;

    address public factory;   // factory that created this pair
    address public token0;    // smaller address
    address public token1;    // larger address

    uint112 private reserve0;           // uses single storage slot, truncates if > uint112
    uint112 private reserve1;
    uint32  private blockTimestampLast;

    // permanent lock of MINIMUM_LIQUIDITY to a non-zero burn address (OpenZeppelin forbids address(0))
    address public constant BURN_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    uint256 public constant MINIMUM_LIQUIDITY = 1000; // locked forever to BURN_ADDRESS
    uint256 public constant FEE_NUM = 997;   // numerator for 0.3% fee
    uint256 public constant FEE_DEN = 1000;  // denominator

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(address indexed sender, uint256 amount0In, uint256 amount1In, uint256 amount0Out, uint256 amount1Out, address indexed to);
    event Sync(uint112 reserve0, uint112 reserve1);

    modifier onlyFactory() {
        require(msg.sender == factory, "Pair: FORBIDDEN");
        _;
    }

    constructor() ERC20("UNI-V2", "UNI-V2") {
        factory = msg.sender; // when factory deploys pair via new Pair()
    }

    /// @notice Called by factory once after deployment to set tokens
    function initialize(address _token0, address _token1) external onlyFactory {
        require(token0 == address(0) && token1 == address(0), "Pair: ALREADY_INITIALIZED");
        require(_token0 != _token1, "Pair: IDENTICAL_ADDRESSES");
        // sort tokens to ensure consistent ordering
        (token0, token1) = _token0 < _token1 ? (_token0, _token1) : (_token1, _token0);
    }

    /// @notice Returns reserves (reserve0, reserve1, lastTimestamp)
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /// @notice Add liquidity; called by Router/externals which transfer tokens in first
    /// @dev Follows Uniswap V2 mint logic
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        require(to != address(0), "Pair: INVALID_TO");

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        require(amount0 > 0 && amount1 > 0, "Pair: INSUFFICIENT_INPUT_AMOUNT");

        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            // initial liquidity: mint sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
            liquidity = (amount0 * amount1).sqrt();
            require(liquidity > MINIMUM_LIQUIDITY, "Pair: INSUFFICIENT_LIQUIDITY_MINTED");
            // permanently lock the minimum liquidity to a non-zero burn address compatible with OpenZeppelin
            _mint(BURN_ADDRESS, MINIMUM_LIQUIDITY);
            _mint(to, liquidity - MINIMUM_LIQUIDITY);
        } else {
            // mint proportional to existing supply
            uint256 liquidity0 = (amount0 * _totalSupply) / _reserve0;
            uint256 liquidity1 = (amount1 * _totalSupply) / _reserve1;
            liquidity = Math.min(liquidity0, liquidity1);
            require(liquidity > 0, "Pair: INSUFFICIENT_LIQUIDITY_MINTED");
            _mint(to, liquidity);
        }

        _update(uint112(balance0), uint112(balance1));
        emit Mint(msg.sender, amount0, amount1);
    }

    /// @notice Remove liquidity and send tokens to `to`
    /// @dev Caller must have transferred LP tokens to this contract or router will handle burning
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        require(to != address(0), "Pair: INVALID_TO");

        uint256 _balance0 = IERC20(token0).balanceOf(address(this));
        uint256 _balance1 = IERC20(token1).balanceOf(address(this));

        uint256 liquidity = balanceOf(address(this));
        require(liquidity > 0, "Pair: INSUFFICIENT_LIQUIDITY_BURNED");

        uint256 _totalSupply = totalSupply();
        amount0 = (liquidity * _balance0) / _totalSupply;
        amount1 = (liquidity * _balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "Pair: INSUFFICIENT_LIQUIDITY_BURNED_AMOUNTS");

        _burn(address(this), liquidity);
        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        // refresh balances after transfer
        uint256 newBalance0 = IERC20(token0).balanceOf(address(this));
        uint256 newBalance1 = IERC20(token1).balanceOf(address(this));
        _update(uint112(newBalance0), uint112(newBalance1));

        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @notice Swap tokens; caller must transfer input tokens in before calling via Router
    /// @param amount0Out amount of token0 to send out
    /// @param amount1Out amount of token1 to send out
    /// @param to recipient address
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external nonReentrant {
        require(to != address(0), "Pair: INVALID_TO");
        require(amount0Out > 0 || amount1Out > 0, "Pair: INSUFFICIENT_OUTPUT_AMOUNT");
    
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "Pair: INSUFFICIENT_LIQUIDITY");
    
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);
    
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
    
        uint256 amount0In = balance0 > (_reserve0 - amount0Out) ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > (_reserve1 - amount1Out) ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, "Pair: INSUFFICIENT_INPUT_AMOUNT");
    
        uint256 balance0Adjusted = balance0 * FEE_DEN - amount0In * (FEE_DEN - FEE_NUM);
        uint256 balance1Adjusted = balance1 * FEE_DEN - amount1In * (FEE_DEN - FEE_NUM);
        require(
            balance0Adjusted * balance1Adjusted >= uint256(_reserve0) * uint256(_reserve1) * (FEE_DEN ** 2),
            "Pair: K"
        );
    
        _update(uint112(balance0), uint112(balance1));
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }


    /// @notice Force reserves to match balances
    function sync() external {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        _update(uint112(balance0), uint112(balance1));
    }

    // ---------- Internal helpers ----------
    function _update(uint112 balance0, uint112 balance1) internal {
        reserve0 = balance0;
        reserve1 = balance1;
        blockTimestampLast = uint32(block.timestamp % 2**32);
        emit Sync(reserve0, reserve1);
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(to != address(0), "Pair: INVALID_TO");
        require(IERC20(token).transfer(to, value), "Pair: TRANSFER_FAILED");
    }
}
