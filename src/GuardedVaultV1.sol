// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {VaultAccessControlUpgradeable} from "./access/VaultAccessControlUpgradeable.sol";
import {EmergencyModuleUpgradeable} from "./EmergencyModuleUpgradeable.sol";

/// @title GuardedVaultV1
/// @notice ERC-4626 vault with access control, emergency modes, and UUPS upgradeability
/// @dev Deployed behind an ERC1967Proxy. Upgrades gated by _authorizeUpgrade().
///
/// Inheritance chain:
///   ERC4626Upgradeable -> ERC20Upgradeable -> Initializable
///   VaultAccessControlUpgradeable -> AccessControlUpgradeable -> Initializable
///   EmergencyModuleUpgradeable -> Initializable
///   UUPSUpgradeable -> Initializable
contract GuardedVaultV1 is
    ERC4626Upgradeable,
    VaultAccessControlUpgradeable,
    EmergencyModuleUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Errors ============

    error CannotSweepUnderlyingAsset();

    // ============ Events ============

    event Swept(address indexed token, address indexed to, uint256 amount);

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initialize the vault (replaces constructor for proxy deployments)
    /// @param asset_ The underlying ERC-20 token
    /// @param name_ The vault share token name
    /// @param symbol_ The vault share token symbol
    /// @param owner_ The initial owner address
    function initialize(
        IERC20 asset_,
        string memory name_,
        string memory symbol_,
        address owner_
    ) external initializer {
        __ERC4626_init(asset_);
        __ERC20_init(name_, symbol_);
        __VaultAccessControl_init(owner_);
        __EmergencyModule_init();
    }

    // ============ UUPS Authorization ============

    /// @notice UUPS authorization — only OWNER_ROLE (timelock) can upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(OWNER_ROLE) {}

    // ============ ERC-4626 Overrides with Emergency Checks ============

    function deposit(
        uint256 assets,
        address receiver
    ) public virtual override whenNotPausedOrWithdrawOnly returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(
        uint256 shares,
        address receiver
    ) public virtual override whenNotPausedOrWithdrawOnly returns (uint256) {
        return super.mint(shares, receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner_
    ) public virtual override whenWithdrawalsAllowed returns (uint256) {
        return super.withdraw(assets, receiver, owner_);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner_
    ) public virtual override whenWithdrawalsAllowed returns (uint256) {
        return super.redeem(shares, receiver, owner_);
    }

    // ============ View Overrides ============

    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function maxDeposit(
        address receiver
    ) public view virtual override returns (uint256) {
        if (emergencyState() != EmergencyState.NORMAL) {
            return 0;
        }
        return super.maxDeposit(receiver);
    }

    function maxMint(
        address receiver
    ) public view virtual override returns (uint256) {
        if (emergencyState() != EmergencyState.NORMAL) {
            return 0;
        }
        return super.maxMint(receiver);
    }

    function maxWithdraw(
        address owner_
    ) public view virtual override returns (uint256) {
        if (emergencyState() == EmergencyState.PAUSED) {
            return 0;
        }
        return super.maxWithdraw(owner_);
    }

    function maxRedeem(
        address owner_
    ) public view virtual override returns (uint256) {
        if (emergencyState() == EmergencyState.PAUSED) {
            return 0;
        }
        return super.maxRedeem(owner_);
    }

    // ============ Emergency Controls ============

    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(OWNER_ROLE) {
        _unpause();
    }

    function setWithdrawOnly() external onlyRole(GUARDIAN_ROLE) {
        _setWithdrawOnly();
    }

    // ============ Token Recovery ============

    function sweep(IERC20 token, address to) external onlyRole(OWNER_ROLE) {
        if (address(token) == asset()) {
            revert CannotSweepUnderlyingAsset();
        }
        uint256 amount = token.balanceOf(address(this));
        token.safeTransfer(to, amount);
        emit Swept(address(token), to, amount);
    }
}
