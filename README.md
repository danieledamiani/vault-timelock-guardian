# Vault Timelock Guardians

ERC-4626 tokenized vault for a single ERC-20 underlying asset, with upgradeability gated by a timelock and limited emergency controls via a guardian role. The goal is to provide a small but production-shaped vault implementation with explicit security properties and a verification-focused test suite.

## What’s included

- ERC-4626 vault: deposit/mint and withdraw/redeem with share accounting and explicit rounding behavior.
- Governance controls:
  - Timelock required for sensitive actions (upgrades, fee/limit changes, strategy changes if enabled).
  - Role separation: owner, (optional) operator, guardian.
- Emergency controls:
  - Pause and withdraw-only modes.
  - Sweep protections for accidental tokens while protecting user funds.
- Observability: events for all privileged actions and state transitions.

## Security and verification

The repository is built around testable properties:

- Unit tests for edge cases, rounding boundaries, and access control.
- Fuzzing and invariants for accounting correctness and mode restrictions.
- Fork tests against real ERC-20 tokens to validate integration assumptions.
- Static analysis in CI (Slither).
- Executable adversarial tests covering common failure modes (reentrancy attempts, share inflation attempts, privileged-role compromise scenarios).

## Quickstart

Prerequisites:

- Foundry installed (`forge`, `cast`)
- (Optional) Node.js for scripts and tooling

Run tests:

```bash
forge test -vvv
```

Run invariants (if separated into a profile):

```bash
forge test --match-path test/invariant/* -vvv
```

Run on a fork (example):

```bash
export ETH_RPC_URL="https://YOUR_RPC"
forge test --fork-url $ETH_RPC_URL -vvv
```

Docs

- docs/spec.md: scope, roles, assumptions, and verification plan.
- docs/threat-model.md: threat model and trust assumptions.
- docs/audit-notes.md: findings, decisions, and remediation log.

Status

This is a learning and engineering portfolio project. The contracts are not audited and are not intended for production use without independent review.
