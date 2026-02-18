// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {GuardedVaultV1} from "../src/GuardedVaultV1.sol";
import {VaultTimelockProxyDeployer} from "../src/deploy/VaultTimelockProxyDeployer.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

/// @title GuardedVaultV2Mock
/// @notice Minimal V2 that adds a version() getter — proves the upgrade worked
/// @dev Inherits everything from V1, adds one function. No new storage needed.
contract GuardedVaultV2Mock is GuardedVaultV1 {
    function version() external pure returns (uint256) {
        return 2;
    }
}

/// @title Upgrade Integration Tests
/// @notice Tests UUPS upgradeability: state preservation across upgrades, authorization gating
/// @dev Deploys V1 through VaultTimelockProxyDeployer, then upgrades to V2Mock through timelock
contract UpgradeIntegrationTest is Test {
    // ============ State Variables ============

    GuardedVaultV1 public vault; // proxy address, cast to V1
    TimelockController public timelock;
    MockERC20 public underlying;

    address public admin = makeAddr("admin"); // timelock PROPOSER
    address public guardian = makeAddr("guardian");
    address public user = makeAddr("user");
    address public attacker = makeAddr("attacker");

    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant DEPOSIT_AMOUNT = 500e18;

    // ============ Setup ============

    function setUp() public {
        // Deploy underlying token
        underlying = new MockERC20("USD Coin", "USDC", 18);

        // Deploy vault (behind ERC1967 proxy) + timelock atomically
        VaultTimelockProxyDeployer deployer = new VaultTimelockProxyDeployer();
        (vault, timelock) = deployer.deploy(
            IERC20(address(underlying)),
            "Guarded Vault USDC",
            "gvUSDC",
            admin,
            guardian,
            MIN_DELAY
        );

        // User deposits into the proxy vault
        underlying.mint(user, DEPOSIT_AMOUNT);
        vm.startPrank(user);
        underlying.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT, user);
        vm.stopPrank();
    }

    // ============ Helpers ============

    /// @dev Deploys V2Mock and returns its address (for use in upgrade calldata)
    function _deployV2() internal returns (address) {
        GuardedVaultV2Mock v2Impl = new GuardedVaultV2Mock();
        return address(v2Impl);
    }

    /// @dev Schedules, waits, and executes a timelocked call on the vault
    function _timelockExecute(bytes memory data) internal {
        vm.prank(admin);
        timelock.schedule(
            address(vault),
            0,
            data,
            bytes32(0),
            bytes32(0),
            MIN_DELAY
        );
        vm.warp(block.timestamp + MIN_DELAY);
        timelock.execute(address(vault), 0, data, bytes32(0), bytes32(0));
    }

    // ============ Upgrade Tests ============
    function test_Upgrade_StatePreservedAfterUpgrade() public {
        // 1. Record user's share balance and vault's totalAssets BEFORE the upgrade
        uint256 userBalanceBefore = vault.balanceOf(user);
        uint256 totalAssetsBefore = vault.totalAssets();

        // 2. Deploy V2Mock with _deployV2()
        address v2Address = _deployV2();

        // 3. Build upgradeToAndCall calldata
        bytes memory encodedData = abi.encodeCall(
            vault.upgradeToAndCall,
            (v2Address, "")
        );

        // 4. Execute through timelock with _timelockExecute(data)
        _timelockExecute(encodedData);

        // 5. Cast proxy to GuardedVaultV2Mock to access version()
        GuardedVaultV2Mock vaultV2 = GuardedVaultV2Mock(address(vault));

        // 6. Assert: version() == 2 (upgrade worked)
        assertEq(vaultV2.version(), 2);

        // 7. Assert: user shares unchanged (balanceOf)
        assertEq(userBalanceBefore, vaultV2.balanceOf(user));

        // 8. Assert: totalAssets unchanged (underlying still there)
        assertEq(totalAssetsBefore, vaultV2.totalAssets());
    }

    function test_Upgrade_OnlyTimelockCanUpgrade() public {
        // Goal: Prove that direct calls to upgradeToAndCall revert for non-owners.
        // Steps:
        // 1. Deploy V2Mock with _deployV2()
        address v2Address = _deployV2();

        // 2. As attacker: vm.prank(attacker) + vm.expectRevert() + vault.upgradeToAndCall(...)
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                bytes32(0)
            )
        );
        vault.upgradeToAndCall(v2Address, "");

        //  3. As admin (not owner, just proposer): same pattern — should also revert
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                admin,
                bytes32(0)
            )
        );
        vault.upgradeToAndCall(v2Address, "");

        // 4. As guardian: same pattern — should also revert
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                guardian,
                bytes32(0)
            )
        );

        vault.upgradeToAndCall(v2Address, "");
    }
}
