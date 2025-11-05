// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TokenA is ERC20, Ownable {
    constructor() ERC20("Token B", "TKB") Ownable(msg.sender){
        _mint(msg.sender, 1_000_000 ether);
    }

    /// @notice Mint new tokens to an address (only owner)
    /// @param to Receiver of the new tokens
    /// @param amount Amount to mint (in whole tokens)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount * 1e18);
    }
} 