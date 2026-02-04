// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice A simple ERC-20 token for testing purposes
/// @dev Exposes mint/burn functions without access control - NEVER use in production
contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    /// @param name_ Token name (e.g., "Mock USDC")
    /// @param symbol_ Token symbol (e.g., "mUSDC")
    /// @param decimals_ Number of decimals (6 for USDC-like, 18 for ETH-like)
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /// @notice Returns the number of decimals for the token
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Mints tokens to an address (testing only)
    /// @param to Address to receive tokens
    /// @param amount Amount of tokens to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burns tokens from an address (testing only)
    /// @param from Address to burn tokens from
    /// @param amount Amount of tokens to burn
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
