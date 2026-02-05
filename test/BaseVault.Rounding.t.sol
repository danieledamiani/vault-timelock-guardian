// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {BaseVault} from "../src/BaseVault.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title BaseVaultRoundingTest
/// @notice Tests rounding behavior and security properties
/// @dev ERC-4626 requires rounding to always FAVOR THE VAULT
contract BaseVaultRoundingTest is Test {
    BaseVault public vault;
    MockERC20 public asset;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public attacker = makeAddr("attacker");

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC", 18);
        vault = new BaseVault(IERC20(address(asset)), "Vault USDC", "vUSDC");

        // Fund accounts generously
        asset.mint(alice, 100_000e18);
        asset.mint(bob, 100_000e18);
        asset.mint(attacker, 100_000e18);

        // Approve vault
        vm.prank(alice);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        asset.approve(address(vault), type(uint256).max);
        vm.prank(attacker);
        asset.approve(address(vault), type(uint256).max);
    }

    // ============ Rounding Direction Tests ============

    /// @notice previewDeposit should round DOWN (fewer shares for user)
    function test_PreviewDeposit_RoundsDown() public {
        // First, create a ratio where rounding matters
        // Alice deposits to establish initial state
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        // Simulate yield: donate tokens to vault (increases totalAssets without minting shares)
        asset.mint(address(vault), 1); // Just 1 wei of "yield"

        // Now: totalAssets = 1000e18 + 1, totalSupply = 1000e18
        // If Bob deposits 1 wei, he should get: 1 * 1000e18 / (1000e18 + 1) = 0 shares (rounds down!)

        uint256 preview = vault.previewDeposit(1);
        assertEq(preview, 0, "previewDeposit should round down to 0");
    }

    /// @notice previewMint should round UP (user pays more assets)
    function test_PreviewMint_RoundsUp() public {
        // Setup ratio
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        // Donate to create non-1:1 ratio
        asset.mint(address(vault), 500e18); // 50% yield

        // Now: totalAssets = 1500e18, totalSupply = 1000e18
        // To mint 1 share, you need: 1 * 1500e18 / 1000e18 = 1.5 assets
        // Should round UP to 2 wei

        uint256 preview = vault.previewMint(1);
        assertGe(preview, 2, "previewMint should round up");
    }

    /// @notice previewWithdraw should round UP (user burns more shares)
    function test_PreviewWithdraw_RoundsUp() public {
        // Setup
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        // Create ratio where rounding is visible
        asset.mint(address(vault), 500e18);

        // To withdraw 1 asset, need: 1 * 1000e18 / 1500e18 = 0.67 shares
        // Should round UP to 1 share (user loses fractional share)

        uint256 preview = vault.previewWithdraw(1);
        assertGe(preview, 1, "previewWithdraw should round up");
    }

    /// @notice previewRedeem should round DOWN (user gets fewer assets)
    function test_PreviewRedeem_RoundsDown() public {
        // Setup
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        asset.mint(address(vault), 500e18);

        // Redeeming 1 share gets: 1 * 1500e18 / 1000e18 = 1.5 assets
        // Should round DOWN to 1 asset

        uint256 preview = vault.previewRedeem(1);
        // At this ratio, 1 share = 1.5 assets, rounds down to 1
        assertEq(preview, 1, "previewRedeem should round down");
    }

    // ============ Share Inflation Attack Demonstration ============

    /// @notice DEMONSTRATES the share inflation attack and OZ's minimal protection
    /// @dev OpenZeppelin v5 adds +1 virtual share and +1 virtual asset
    /// @dev This REDUCES but does NOT eliminate the attack — victim still loses 100%!
    function test_ShareInflationAttack_PartialMitigation() public {
        // ATTACK SCENARIO:
        // 1. Attacker is first depositor with 1 wei → gets 1 share
        // 2. Attacker donates 10000e18 assets directly to vault
        // 3. Now: totalAssets = 10000e18 + 1, totalSupply = 1
        // 4. Victim deposits 5000e18 → math includes virtual shares/assets
        // 5. Attacker redeems 1 share

        // Step 1: Attacker deposits 1 wei
        vm.prank(attacker);
        vault.deposit(1, attacker);
        assertEq(vault.balanceOf(attacker), 1, "Attacker should have 1 share");

        // Step 2: Attacker donates to inflate share price
        asset.mint(address(vault), 10_000e18);

        // Now check: totalAssets = 10000e18 + 1, totalSupply = 1 share
        assertEq(vault.totalAssets(), 10_000e18 + 1);
        assertEq(vault.totalSupply(), 1);

        // Step 3: Victim tries to deposit 5000e18
        // OZ formula: shares = assets * (totalSupply + 1) / (totalAssets + 1)
        // = 5000e18 * (1 + 1) / (10000e18 + 1 + 1) = 5000e18 * 2 / 10000e18 ≈ 1
        // But with such a large ratio, this still rounds to 0!
        uint256 victimDepositAmount = 5000e18;
        uint256 victimSharesPreview = vault.previewDeposit(victimDepositAmount);

        vm.prank(bob);
        uint256 actualShares = vault.deposit(victimDepositAmount, bob);

        // PROOF OF VULNERABILITY: victim STILL gets 0 shares even with OZ's protection!
        // The +1 virtual share isn't enough against a 10000e18 donation
        assertEq(actualShares, 0, "Victim still gets 0 shares");
        assertEq(
            victimSharesPreview,
            0,
            "Preview correctly predicted 0 shares"
        );

        // Step 4: Verify attacker steals significant value
        uint256 attackerCanRedeem = vault.previewRedeem(1); // Attacker has 1 share
        emit log_named_uint("Attacker's 1 share is worth", attackerCanRedeem);
        emit log_named_uint("Total assets in vault", vault.totalAssets());

        // OZ's virtual shares mean attacker gets: 1 * (totalAssets+1) / (totalSupply+1)
        // = 1 * (15000e18 + 2) / (1 + 1) = ~7500e18
        // So attacker gets ~50% and the other ~50% is "stuck" belonging to the virtual share
        uint256 expectedAttackerAmount = (15_000e18 + 2) / 2;
        assertEq(
            attackerCanRedeem,
            expectedAttackerAmount,
            "Attacker gets ~50% of all assets"
        );

        // KEY INSIGHT: Victim lost 100% of their 5000e18 deposit!
        // ~2500e18 went to attacker's profit, ~2500e18 is stuck in the virtual share
        // The OZ mitigation reduced attacker profit but DID NOT protect the victim

        // This is why we need a stronger defense:
        // Option 1: Override _decimalsOffset() to return 3-6 (adds more virtual shares)
        // Option 2: Require minimum first deposit
        // Option 3: Dead shares on first deposit
    }

    // ============ No Free Shares Tests ============

    /// @notice Depositing when share price is high should never give free shares
    /// @dev This test demonstrates the rounding behavior with a high share price
    function test_NoFreeShares_HighPriceDeposit() public {
        // Alice establishes vault with initial deposit
        vm.prank(alice);
        vault.deposit(1e18, alice); // 1e18 assets = 1e18 shares

        // Donate to make 1 share worth 1000 assets
        asset.mint(address(vault), 999e18);

        // Now: totalAssets = 1000e18, totalSupply = 1e18
        // So 1 share = 1000 assets, meaning 1 asset = 0.001 shares

        // Depositing 500e18 should give: 500e18 * 1e18 / 1000e18 = 0.5e18 shares
        uint256 sharesFor500 = vault.previewDeposit(500e18);
        assertEq(
            sharesFor500,
            0.5e18,
            "500e18 assets should give 0.5e18 shares"
        );

        // Depositing 1000e18 gives exactly 1e18 shares
        uint256 sharesFor1000 = vault.previewDeposit(1000e18);
        assertEq(sharesFor1000, 1e18, "1000e18 assets should give 1e18 shares");

        // The key test: depositing a tiny amount rounds DOWN to 0
        // 1 wei of assets = 1 * 1e18 / 1000e18 = 0.000000000000001 shares → rounds to 0
        uint256 sharesFor1Wei = vault.previewDeposit(1);
        assertEq(sharesFor1Wei, 0, "1 wei should give 0 shares (rounds down)");
    }

    /// @notice Redeeming 1 share should give at least floor(shareValue) assets
    function test_NoExtraAssets_Redeem() public {
        vm.prank(alice);
        vault.deposit(1000e18, alice);

        // Add yield: now 1000 shares = 1500 assets
        asset.mint(address(vault), 500e18);

        // Each share is worth 1.5 assets
        // Redeeming 1 share should give 1 asset (floor), not 2 (ceiling)
        uint256 assets = vault.previewRedeem(1);
        assertEq(assets, 1, "1 share should redeem for 1 asset (floor of 1.5)");
    }

    // ============ Fuzz Tests for Invariants ============

    /// @notice Fuzz: depositing then immediately redeeming should never profit
    function testFuzz_NoInstantProfit(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, 50_000e18);

        // Create some existing state (non-empty vault)
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        // Maybe add some yield
        asset.mint(address(vault), 1000e18);

        uint256 bobBalanceBefore = asset.balanceOf(bob);

        // Bob deposits
        vm.prank(bob);
        uint256 shares = vault.deposit(depositAmount, bob);

        // Bob immediately redeems everything
        vm.prank(bob);
        uint256 assetsBack = vault.redeem(shares, bob, bob);

        uint256 bobBalanceAfter = asset.balanceOf(bob);

        // Bob should never profit from instant round-trip
        assertLe(
            bobBalanceAfter,
            bobBalanceBefore,
            "User should not profit from instant deposit/redeem"
        );
        assertLe(
            assetsBack,
            depositAmount,
            "Assets received should not exceed assets deposited"
        );
    }

    /// @notice Fuzz: preview functions should never lie in user's favor
    function testFuzz_PreviewNeverLiesInUserFavor(
        uint256 depositAmount,
        uint256 yieldAmount
    ) public {
        depositAmount = bound(depositAmount, 100, 50_000e18);
        yieldAmount = bound(yieldAmount, 0, 10_000e18);

        // Setup vault
        vm.prank(alice);
        vault.deposit(10_000e18, alice);

        // Add yield
        if (yieldAmount > 0) {
            asset.mint(address(vault), yieldAmount);
        }

        // Test deposit preview
        uint256 previewShares = vault.previewDeposit(depositAmount);
        vm.prank(bob);
        uint256 actualShares = vault.deposit(depositAmount, bob);
        assertLe(
            actualShares,
            previewShares,
            "Actual shares <= preview shares"
        );

        // Test redeem preview
        uint256 previewAssets = vault.previewRedeem(actualShares);
        vm.prank(bob);
        uint256 actualAssets = vault.redeem(actualShares, bob, bob);
        assertLe(
            actualAssets,
            previewAssets,
            "Actual assets <= preview assets"
        );
    }
}
