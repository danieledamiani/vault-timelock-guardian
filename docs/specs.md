# Vault Timelock Guardians

## Summary

This repository implements an ERC-4626 tokenized vault with controlled administration. The vault supports upgradeable logic, with upgrades and other sensitive parameters gated behind a timelock. A separate guardian role can trigger limited emergency actions (pause and withdraw-only) without bypassing the timelock.

The project is designed to be verifiable. It includes a Foundry test suite covering unit tests, fuzzing, invariants, fork tests against real ERC-20 tokens, static analysis in CI, and executable adversarial tests for common failure modes (reentrancy attempts, share inflation, and privileged-role compromise scenarios).

## Goals

- Implement a correct ERC-4626 vault with predictable share accounting.
- Separate privileges into roles with clear, enforceable boundaries.
- Require timelock delay for sensitive actions (upgrades, fees, strategy changes).
- Provide emergency controls that reduce blast radius without creating a backdoor.
- Make correctness properties explicit and testable via invariants and fuzzing.

## Non-goals

- Providing real yield strategies. The strategy interface may be stubbed or mocked.
- Cross-chain support.
- Governance token mechanics.
- MEV protection beyond standard best practices.
- Full economic security analysis of an external strategy.

## Actors and roles

- **User**: deposits assets and receives shares; redeems shares for assets.
- **Owner**: configures governance addresses and can schedule privileged actions via the timelock.
- **Operator**: performs routine operations permitted by policy (optional, may be omitted in v1).
- **Guardian**: can trigger emergency modes (pause, withdraw-only) and cannot upgrade or change fees.
- **Timelock**: the only entity allowed to execute sensitive actions after a delay.

## Core features

- **ERC-4626 vault**
  - Deposit/mint and withdraw/redeem flows.
  - Share accounting with explicit rounding choices.
  - Optional fees and limits (configurable, with safe defaults).
- **Administration and governance**
  - Role-based access control.
  - Timelock gated administration for sensitive actions.
- **Upgradeability**
  - Proxy-based upgrade mechanism.
  - Upgrades executable only by the timelock.
  - Initializer protections and storage layout discipline.
- **Emergency controls**
  - Pause: blocks deposits and mints.
  - Withdraw-only: allows withdrawals and redemptions; blocks deposits and mints.
  - Sweep protections: restrict recovery of non-vault tokens while protecting user funds.
- **Observability**
  - Events emitted for all privileged actions and state transitions.

## Trust assumptions

- The underlying ERC-20 asset is assumed not to be malicious; deviations are tested via mocks.
- The owner and timelock admin are assumed not to be compromised; guardian exists to reduce damage during incidents, not to replace governance.
- External strategy contracts (if enabled) are not trusted by default; integration is treated as an explicit risk.

## Security properties (high level)

The system must maintain these properties across all valid call sequences:

- Users cannot withdraw more assets than their shares entitle them to.
- Total shares and total assets remain consistent with ERC-4626 semantics.
- Privileged operations (fee changes, upgrades, strategy changes) cannot occur without timelock delay.
- Guardian actions cannot be used to seize funds, change governance, or bypass timelock.
- Emergency modes correctly restrict the allowed operation set.

## Test and verification plan

- **Unit tests**: rounding boundaries, preview vs actual behavior, fee math, role restrictions.
- **Fuzzing**: random deposits/withdrawals across multiple actors and edge values.
- **Invariants**: accounting correctness, mode restrictions, privilege boundaries.
- **Fork tests**: run against real tokens on a fork to validate integration assumptions.
- **Static analysis**: Slither (and optionally Mythril) in CI with reviewed findings.
- **Attack tests**: executable tests for reentrancy attempts, share inflation attempts, and compromised privileged-role scenarios.
