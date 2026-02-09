// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {VaultAccessControl} from "./access/VaultAccessControl.sol";
import {EmergencyModule} from "./EmergencyModule.sol";

/// @title GuardedVault
/// @notice ERC-4626 vault with access control and emergency modes
/// @dev Combines BaseVault + VaultAccessControl + EmergencyModule
///
/// Features:
/// - ERC-4626 compliant tokenized vault
/// - Role-based access control (Owner, Guardian, Operator)
/// - Emergency states (Normal, Paused, Withdraw-Only)
/// - Sweep function to recover accidentally-sent tokens
///
/// Security Properties:
/// - Guardian can pause or set withdraw-only mode
/// - Only Owner can unpause/return to normal
/// - Users can always eventually withdraw (no permanent fund lock)
/// - Rounding always favors the vault
/// - Cannot sweep the vault's underlying asset (protects user deposits)
contract GuardedVault is ERC4626, VaultAccessControl, EmergencyModule {
    using SafeERC20 for IERC20;

    // ============ Errors ============

    /// @notice Thrown when trying to sweep the vault's underlying asset
    error CannotSweepUnderlyingAsset();

    // ============ Events ============

    /// @notice Emitted when tokens are swept from the vault
    /// @param token The token that was swept
    /// @param to The recipient address
    /// @param amount The amount of tokens swept
    event Swept(address indexed token, address indexed to, uint256 amount);

    // ============ Constructor ============

    /// @param asset_ The underlying ERC-20 token (e.g., USDC)
    /// @param name_ The vault share token name (e.g., "Guarded Vault USDC")
    /// @param symbol_ The vault share token symbol (e.g., "gvUSDC")
    /// @param owner_ The initial owner address
    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_
    )
        ERC4626(asset_)
        ERC20(name_, symbol_)
        VaultAccessControl(owner_)
        EmergencyModule()
    {}

    // ============ ERC-4626 Overrides with Emergency Checks ============

    /// @notice Deposit assets and receive shares
    /// @dev Blocked when paused or in withdraw-only mode
    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override whenNotPausedOrWithdrawOnly returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @notice Mint exact shares by depositing assets
    /// @dev Blocked when paused or in withdraw-only mode
    function mint(
        uint256 shares,
        address receiver
    ) public virtual override whenNotPausedOrWithdrawOnly returns (uint256) {
        return super.mint(shares, receiver);
    }

    /// @notice Withdraw assets by burning shares
    /// @dev Allowed in NORMAL and WITHDRAW_ONLY, blocked when PAUSED
    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    ) public virtual override whenWithdrawalsAllowed returns (uint256) {
        return super.withdraw(assets, receiver, owner_);
    }

    /// @notice Redeem shares for assets
    /// @dev Allowed in NORMAL and WITHDRAW_ONLY, blocked when PAUSED
    function redeem(
        uint256 shares,
        address receiver,
        address owner_
    ) public virtual override whenWithdrawalsAllowed returns (uint256) {
        return super.redeem(shares, receiver, owner_);
    }

    // ============ View Overrides ============

    /// @notice Returns total assets managed by the vault
    /// @dev Source of truth for share calculations
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Maximum depositable assets
    /// @dev Returns 0 when deposits are blocked
    function maxDeposit(
        address receiver
    ) public view virtual override returns (uint256) {
        if (emergencyState() != EmergencyState.NORMAL) {
            return 0;
        }
        return super.maxDeposit(receiver);
    }

    /// @notice Maximum mintable shares
    /// @dev Returns 0 when minting is blocked
    function maxMint(
        address receiver
    ) public view virtual override returns (uint256) {
        if (emergencyState() != EmergencyState.NORMAL) {
            return 0;
        }
        return super.maxMint(receiver);
    }

    /// @notice Maximum withdrawable assets
    /// @dev Returns 0 when paused, normal max otherwise
    function maxWithdraw(
        address owner_
    ) public view virtual override returns (uint256) {
        if (emergencyState() == EmergencyState.PAUSED) {
            return 0;
        }
        return super.maxWithdraw(owner_);
    }

    /// @notice Maximum redeemable shares
    /// @dev Returns 0 when paused, normal max otherwise
    function maxRedeem(
        address owner_
    ) public view virtual override returns (uint256) {
        if (emergencyState() == EmergencyState.PAUSED) {
            return 0;
        }
        return super.maxRedeem(owner_);
    }

    // ============ Emergency Controls (Public Interface) ============

    /// @notice Pause all vault operations
    /// @dev Only callable by Guardian or Owner
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /// @notice Return to normal operations
    /// @dev Only callable by Owner - guardian cannot unpause!
    function unpause() external onlyRole(OWNER_ROLE) {
        _unpause();
    }

    /// @notice Set withdraw-only mode
    /// @dev Only callable by Guardian
    /// @dev Allows users to exit but prevents new deposits
    function setWithdrawOnly() external onlyRole(GUARDIAN_ROLE) {
        _setWithdrawOnly();
    }

    // ============ Token Recovery ============

    /// @notice Sweep accidentally-sent tokens to a recipient
    /// @dev CRITICAL: Cannot sweep the vault's underlying asset!
    /// @param token The ERC-20 token to sweep
    /// @param to The recipient address for recovered tokens
    function sweep(IERC20 token, address to) external onlyRole(OWNER_ROLE) {
        // CRITICAL PROTECTION: Never allow sweeping the underlying asset
        // This would drain user deposits!
        if (address(token) == asset()) {
            revert CannotSweepUnderlyingAsset();
        }

        // Get the full balance of the accidentally-sent token
        uint256 amount = token.balanceOf(address(this));

        // Transfer using SafeERC20 (handles non-standard tokens like USDT)
        token.safeTransfer(to, amount);

        // Emit event for transparency and off-chain tracking
        emit Swept(address(token), to, amount);
    }
}
