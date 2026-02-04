// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @title MockERC20Test
/// @notice Tests for the MockERC20 token
contract MockERC20Test is Test {
    MockERC20 public token;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant INITIAL_MINT = 1000e18; // 1000 tokens with 18 decimals

    function setUp() public {
        // Deploy token with 18 decimals (ETH-like)
        token = new MockERC20("Mock Token", "MTK", 18);

        // Give Alice some tokens to work with
        token.mint(alice, INITIAL_MINT);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsNameAndSymbol() public view {
        assertEq(token.name(), "Mock Token");
        assertEq(token.symbol(), "MTK");
    }

    function test_Constructor_SetsDecimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_Constructor_DifferentDecimals() public {
        // USDC uses 6 decimals
        MockERC20 usdc = new MockERC20("Mock USDC", "mUSDC", 6);
        assertEq(usdc.decimals(), 6);
    }

    // ============ Mint Tests ============

    function test_Mint_IncreasesBalance() public {
        uint256 balanceBefore = token.balanceOf(bob);

        token.mint(bob, 500e18);

        assertEq(token.balanceOf(bob), balanceBefore + 500e18);
    }

    function test_Mint_IncreasesTotalSupply() public {
        uint256 supplyBefore = token.totalSupply();

        token.mint(bob, 500e18);

        assertEq(token.totalSupply(), supplyBefore + 500e18);
    }

    // ============ Transfer Tests ============

    function test_Transfer_MovesTokens() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);

        assertEq(token.balanceOf(alice), INITIAL_MINT - 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_Transfer_ReturnsTrue() public {
        vm.prank(alice);
        bool success = token.transfer(bob, 100e18);

        assertTrue(success);
    }

    function test_Transfer_RevertsOnInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(); // ERC20: transfer amount exceeds balance
        token.transfer(bob, INITIAL_MINT + 1);
    }

    // ============ Approval & TransferFrom Tests ============

    // This tests the "approval dance" - the two-step process for authorized transfers
    function test_Approve_And_TransferFrom() public {
        // Store initial balances BEFORE any pranks (reading doesn't need prank)
        uint256 aliceInitialBalance = token.balanceOf(alice);
        uint256 bobInitialBalance = token.balanceOf(bob);

        // 1. Alice approves Bob to spend 200e18 tokens
        vm.prank(alice); // This prank ONLY applies to the next call
        token.approve(bob, 200e18);

        // 2. Verify the allowance is set correctly
        uint256 aliceAllowance = token.allowance(alice, bob);
        assertEq(aliceAllowance, 200e18);

        // 3. Bob (acting as msg.sender) calls transferFrom to move 150e18 from Alice to himself
        vm.prank(bob);
        token.transferFrom(alice, bob, 150e18); // Note: from=alice, to=bob

        // 4. Verify Alice's balance decreased
        assertEq(token.balanceOf(alice), aliceInitialBalance - 150e18);

        // 5. Verify Bob's balance increased
        assertEq(token.balanceOf(bob), bobInitialBalance + 150e18);

        // 6. Verify the allowance decreased by the amount transferred
        assertEq(token.allowance(alice, bob), aliceAllowance - 150e18);
    }

    // ============ Burn Tests ============

    function test_Burn_DecreasesBalance() public {
        uint256 balanceBefore = token.balanceOf(alice);

        token.burn(alice, 100e18);

        assertEq(token.balanceOf(alice), balanceBefore - 100e18);
    }

    function test_Burn_DecreasesTotalSupply() public {
        uint256 supplyBefore = token.totalSupply();

        token.burn(alice, 100e18);

        assertEq(token.totalSupply(), supplyBefore - 100e18);
    }

    // ============ Fuzz Tests ============

    /// @notice Fuzz test: mint any amount to any address
    function testFuzz_Mint(address to, uint256 amount) public {
        // Skip zero address (ERC20 reverts on mint to zero)
        vm.assume(to != address(0));
        // Avoid overflow on totalSupply
        vm.assume(amount <= type(uint256).max - token.totalSupply());

        uint256 balanceBefore = token.balanceOf(to);

        token.mint(to, amount);

        assertEq(token.balanceOf(to), balanceBefore + amount);
    }

    /// @notice Fuzz test: transfer respects balance constraints
    function testFuzz_Transfer(uint256 amount) public {
        // Bound amount to Alice's balance
        amount = bound(amount, 0, token.balanceOf(alice));

        vm.prank(alice);
        bool success = token.transfer(bob, amount);

        assertTrue(success);
        assertEq(token.balanceOf(bob), amount);
    }
}
