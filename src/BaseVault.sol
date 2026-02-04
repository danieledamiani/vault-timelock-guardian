// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BaseVault
/// @notice A minimal ERC-4626 vault with no fees or access control
/// @dev This is our foundation - we'll add features on top of this
contract BaseVault is ERC4626 {
    using SafeERC20 for IERC20;

    /// @param asset_ The underlying ERC-20 token (e.g., USDC)
    /// @param name_ The vault share token name (e.g., "Vault USDC")
    /// @param symbol_ The vault share token symbol (e.g., "vUSDC")
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_, symbol_) {}

    /// @notice Returns total assets managed by the vault
    /// @dev This is the SOURCE OF TRUTH for share calculations
    /// @dev In a real vault, this might include external yield
    function totalAssets() public view override returns (uint256) {
        // For now, just the balance held by the vault
        // Later: could add yield from strategies
        return IERC20(asset()).balanceOf(address(this));
    }
}
