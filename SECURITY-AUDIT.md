# Stake Protocol Security Audit Report

**Date**: 2026-02-23
**Scope**: PRs #1 through #5 (merge commits reviewed)
**Auditor**: Automated Security Review

---

## Executive Summary

This audit reviewed five pull requests comprising the initial Stake Protocol codebase: the core smart contract and specification (PR #1), protocol review with tests and deployment scripts (PR #2), CI infrastructure (PR #3), EIP draft (PR #4), and verification documentation (PR #5). The protocol implements a soulbound equity certificate system using ERC-721 and ERC-5192.

**Overall Assessment**: The protocol design is sound. No critical vulnerabilities were identified. Several medium and low severity issues were found, primarily around soulbound enforcement robustness (fixed in PR #2), centralization risks, spec-implementation gaps, and CI configuration weaknesses.

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 5 |
| Low | 7 |
| Informational | 5 |

---

## PR #1: "Add complete Stake Protocol specification and reference implementation"

**Commit**: `eb28517d5f93cdeaf31b7fbbec8dc5aaeb6a5b31`
**Files**: `contracts/src/StakeCertificates.sol`, `spec/STAKE-PROTOCOL.md`, `README.md`, `SECURITY.md`, `CONTRIBUTING.md`, `.gitignore`, `contracts/foundry.toml`

### Finding 1 — Fragile Soulbound Enforcement via Public Function Overrides

| Attribute | Value |
|-----------|-------|
| **Severity** | High |
| **File** | `contracts/src/StakeCertificates.sol` |
| **Lines** | 153–174 (PR #1 version) |
| **Status** | Fixed in PR #2 |

**Description**: The PR #1 implementation enforces non-transferability by overriding public ERC-721 functions (`approve`, `setApprovalForAll`, `transferFrom`, `safeTransferFrom`) as `public pure` functions that revert. This approach is fragile and incorrect for OpenZeppelin v5.

In OpenZeppelin v5, the canonical mechanism to enforce transfer restrictions is overriding the internal `_update` hook, which is the single internal function called for all token movements (mint, transfer, burn). The PR #1 approach has two weaknesses:

1. **Internal hook bypass**: The internal `_update`, `_approve`, and `_setApprovalForAll` functions are not overridden. Any derived contract that calls these internal functions directly would bypass the soulbound restriction.
2. **Inconsistent approval blocking**: While `approve()` is blocked at the public level, `_approve()` remains unblocked internally, allowing internal code paths to set approvals on soulbound tokens.

For the exact code as written in PR #1 (no derived contracts), external callers cannot bypass the restriction because `_update` is `internal`. However, this implementation is not safe for inheritance and does not follow OpenZeppelin v5 best practices.

**Original code (PR #1)**:
```solidity
function approve(address, uint256) public pure override { revert Soulbound(); }
function setApprovalForAll(address, bool) public pure override { revert Soulbound(); }
function transferFrom(address, address, uint256) public pure override { revert Soulbound(); }
function safeTransferFrom(address, address, uint256) public pure override { revert Soulbound(); }
function safeTransferFrom(address, address, uint256, bytes memory) public pure override { revert Soulbound(); }
```

**Fixed code (PR #2)**:
```solidity
function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
    address from = _ownerOf(tokenId);
    if (from != address(0) && to != address(0)) revert Soulbound();
    return super._update(to, tokenId, auth);
}

function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal virtual override {
    if (to != address(0)) revert Soulbound();
    super._approve(to, tokenId, auth, emitEvent);
}

function _setApprovalForAll(address owner, address operator, bool approved) internal virtual override {
    if (approved) revert Soulbound();
    super._setApprovalForAll(owner, operator, approved);
}
```

**Recommendation**: Already resolved in PR #2. The `_update` hook approach is correct and comprehensive.

---

### Finding 2 — Centralized Authority with No Separation of Powers

| Attribute | Value |
|-----------|-------|
| **Severity** | Medium |
| **File** | `contracts/src/StakeCertificates.sol` |
| **Lines** | 592–601 (current) |

**Description**: The `StakeCertificates` constructor grants both `DEFAULT_ADMIN_ROLE` and `AUTHORITY_ROLE` to a single `authority` address. The `DEFAULT_ADMIN_ROLE` holder can grant or revoke any role, including `AUTHORITY_ROLE` itself. This means a single compromised address can:

- Issue unlimited certificates to arbitrary addresses
- Void any claim
- Revoke any stake (where Pact permits)
- Amend mutable Pacts
- Grant `AUTHORITY_ROLE` to other addresses
- Revoke `AUTHORITY_ROLE` from legitimate parties

The spec acknowledges this in Section 14.1: "Issuer authority should be a multisig. The reference code uses a single issuer role for simplicity." However, the contract provides no mechanism to enforce multisig usage, timelocks, or role separation.

**Recommendation**: For production deployments, consider:
- Separating `DEFAULT_ADMIN_ROLE` from `AUTHORITY_ROLE`
- Adding a timelock for sensitive operations (e.g., `amendPact`, `revokeStake`)
- Documenting clearly that `authority` MUST be a multisig or governance contract

---

### Finding 3 — No Emergency Pause Mechanism

| Attribute | Value |
|-----------|-------|
| **Severity** | Medium |
| **File** | `contracts/src/StakeCertificates.sol` |
| **Lines** | All |

**Description**: The contracts have no circuit breaker or pause mechanism. If a vulnerability is discovered post-deployment, there is no way to halt operations without deploying a new contract. The spec mentions this in Section 14.4 as a consideration but the reference implementation omits it entirely.

**Recommendation**: Consider adding OpenZeppelin's `Pausable` with pause/unpause gated by `DEFAULT_ADMIN_ROLE`. Critical functions like `issueClaim`, `redeemToStake`, `revokeStake`, and `mintStake` should check the paused state.

---

### Finding 4 — RevocationMode.ANY Allows Revoking Fully Vested Stakes

| Attribute | Value |
|-----------|-------|
| **Severity** | Medium |
| **File** | `contracts/src/StakeCertificates.sol` |
| **Lines** | 533–556 (current) |

**Description**: When a Pact has `revocationMode` set to `ANY`, the `revokeStake` function allows the authority to revoke any stake regardless of vesting status — including fully vested stakes. The only checks are that the revocation mode is not `NONE` and the stake isn't already revoked. For `ANY` mode, there is no vesting check at all.

This gives the authority unilateral power to confiscate fully vested ownership positions, which may conflict with the protocol's alignment goals. While this is technically "by design" (the Pact governs what's allowed), the power asymmetry is significant.

```solidity
// In revokeStake:
if (p.revocationMode == RevocationMode.NONE) revert RevocationDisabled();

if (p.revocationMode == RevocationMode.UNVESTED_ONLY) {
    if (!s.revocableUnvested) revert RevocationDisabled();
    uint256 unvested = unvestedUnits(stakeId);
    if (unvested == 0) revert StakeFullyVested();
}
// RevocationMode.ANY falls through with no vesting check
s.revoked = true;
```

**Recommendation**: Consider whether `RevocationMode.ANY` should require an additional confirmation step or timelock. At minimum, document this behavior prominently so Pact creators understand the implications.

---

### Finding 5 — Registry Admin Can Bypass Coordinator Contract

| Attribute | Value |
|-----------|-------|
| **Severity** | Low |
| **File** | `contracts/src/StakeCertificates.sol` |
| **Lines** | 599 |

**Description**: The `StakePactRegistry` is created with `authority` as `DEFAULT_ADMIN_ROLE` holder and `StakeCertificates` as `OPERATOR_ROLE` holder. The `authority` can use the admin role to directly grant itself `OPERATOR_ROLE` on the registry, then call `createPact` and `amendPact` directly on the registry, bypassing any future validation logic in the coordinator contract.

```solidity
REGISTRY = new StakePactRegistry(authority, address(this));
```

**Recommendation**: Consider having only the `StakeCertificates` contract as admin of the registry, or remove admin privileges from the authority address on the registry.

---

### Finding 6 — Redundant Pact Existence Check

| Attribute | Value |
|-----------|-------|
| **Severity** | Low |
| **File** | `contracts/src/StakeCertificates.sol` |
| **Lines** | 364–365, 509–510 (current) |

**Description**: In `SoulboundClaim.issueClaim` and `SoulboundStake.mintStake`, after calling `REGISTRY.getPact(pactId)` (which already reverts with `PactNotFound` if the pact doesn't exist), the code performs an additional check `if (p.pactId == bytes32(0)) revert PactNotFound()`. This check is unreachable since `getPact` would have already reverted.

```solidity
Pact memory p = REGISTRY.getPact(pactId);
if (p.pactId == bytes32(0)) revert PactNotFound(); // unreachable
```

**Recommendation**: Remove the redundant check to save gas.

---

### Finding 7 — Spec-Implementation Discrepancies

| Attribute | Value |
|-----------|-------|
| **Severity** | Medium |
| **File** | `spec/STAKE-PROTOCOL.md`, `contracts/src/StakeCertificates.sol` |
| **Lines** | Various |

**Description**: Multiple fields defined in the specification are absent from the reference implementation:

| Spec Field | Location | Implementation Status |
|------------|----------|----------------------|
| `amendment_mode` | Pact (Section 5.2) | Not implemented |
| `amendment_scope` | Pact (Section 5.2) | Not implemented |
| `signing_mode` | Pact (Section 5.2) | Not implemented |
| `dispute_law` | Pact (Section 5.2) | Not implemented |
| `dispute_venue` | Pact (Section 5.2) | Not implemented |
| `custom_terms_hash` | Pact (Section 5.2) | Not implemented |
| `unit_type` | Certificate (Section 6.1) | Enum defined but unused |
| `status_flags` bitfield | Certificate (Section 6.2) | Uses separate booleans instead |
| `conversionHash` | Claim (Section 6.3) | Not implemented |
| `vestingHash` | Stake (Section 6.4) | Not implemented |

The `UnitType` enum is defined in the contract (lines 45–50) but never used by any function or struct.

**Recommendation**: Either update the spec to match the reference implementation scope, or add a clear "Reference Implementation Scope" section listing which spec features are intentionally omitted. Remove the unused `UnitType` enum if it's not needed.

---

### Finding 8 — No Event for Base URI Change

| Attribute | Value |
|-----------|-------|
| **Severity** | Low |
| **File** | `contracts/src/StakeCertificates.sol` |
| **Lines** | 124–126 (current) |

**Description**: The `setBaseURI` function changes the base URI for all token metadata but emits no event. Off-chain indexers and monitoring systems would have no way to detect URI changes.

```solidity
function setBaseURI(string calldata newBaseURI) external onlyRole(ISSUER_ROLE) {
    _baseTokenURI = newBaseURI;
}
```

**Recommendation**: Emit an event when the base URI is changed:
```solidity
event BaseURIUpdated(string newBaseURI);
```

---

### Finding 9 — Vesting Calculation Timestamp Dependency

| Attribute | Value |
|-----------|-------|
| **Severity** | Low |
| **File** | `contracts/src/StakeCertificates.sol` |
| **Lines** | 463–478 (current) |

**Description**: The `vestedUnits` function relies on `block.timestamp` for vesting calculations. Block proposers can manipulate timestamps within a bounded range (~12 seconds on Ethereum). While this is a known limitation acknowledged in the EIP draft (PR #4), it means vesting boundaries are not precise to the second.

**Recommendation**: This is a known and accepted limitation. Document that vesting calculations should not be relied upon for sub-minute precision.

---

## PR #2: "Review stake protocol"

**Commit**: `6c891723a4548627732164bc54a8de45cbeab95c`
**Files**: `contracts/src/StakeCertificates.sol`, `contracts/test/StakeCertificates.t.sol`, `contracts/script/Deploy.s.sol`, `contracts/.env.example`, `contracts/foundry.toml`, `contracts/remappings.txt`, `.gitmodules`

### Finding 10 — Deploy Script Private Key in Environment Variables

| Attribute | Value |
|-----------|-------|
| **Severity** | Low |
| **File** | `contracts/script/Deploy.s.sol`, `contracts/.env.example` |
| **Lines** | Deploy.s.sol:28, .env.example:2 |

**Description**: The deployment script reads the deployer's private key from the `DEPLOYER_PRIVATE_KEY` environment variable. While this is standard Foundry practice, the `.env.example` file explicitly shows the format `DEPLOYER_PRIVATE_KEY=0x...`, which could lead developers to store real private keys in `.env` files. The `.gitignore` does not include `.env` files.

```
# .env.example
DEPLOYER_PRIVATE_KEY=0x...
```

**Recommendation**: Add `.env` and `.env.*` patterns to `.gitignore`. Add a comment in `.env.example` warning against committing real keys. Consider supporting hardware wallet deployment via `--ledger` flag.

---

### Finding 11 — Soulbound Fix Correctly Applied

| Attribute | Value |
|-----------|-------|
| **Severity** | Informational |
| **File** | `contracts/src/StakeCertificates.sol` |
| **Lines** | 143–166 (current) |

**Description**: PR #2 correctly replaces the fragile public function override approach from PR #1 with internal hook overrides (`_update`, `_approve`, `_setApprovalForAll`). This is the proper OpenZeppelin v5 pattern. The fix also correctly allows burning (from != 0, to == 0) while blocking transfers (from != 0, to != 0).

**Status**: Positive finding. No action needed.

---

### Finding 12 — Test Coverage Gaps

| Attribute | Value |
|-----------|-------|
| **Severity** | Informational |
| **File** | `contracts/test/StakeCertificates.t.sol` |
| **Lines** | Various |

**Description**: While the test suite is comprehensive, the following scenarios are not tested:

1. **Role management**: No tests for granting/revoking `AUTHORITY_ROLE` to additional addresses
2. **Burning**: No tests for token burning paths (the `_update` override allows it)
3. **Multiple recipients**: No tests for issuing to many different recipients
4. **Pact amendment effect on existing certificates**: No tests verifying existing certificates remain bound to old pact after amendment
5. **Concurrent idempotent operations**: No tests for rapid sequential calls with same issuance/redemption IDs
6. **Fuzz testing**: No fuzz tests for vesting calculation edge cases (e.g., very large units, extreme timestamps)

**Recommendation**: Add fuzz tests for vesting calculations and tests for the scenarios above.

---

## PR #3: "Add CI workflow, gas snapshots, and README badges"

**Commit**: `a17f507d05ec807e14b674cb824cea31aa395465`
**Files**: `.github/workflows/ci.yml`, `README.md`, `contracts/.gas-snapshot`

### Finding 13 — Slither Security Scanner Set to Continue on Error

| Attribute | Value |
|-----------|-------|
| **Severity** | Medium |
| **File** | `.github/workflows/ci.yml` |
| **Lines** | 59 |

**Description**: The Slither static analysis job uses `continue-on-error: true`, meaning security findings from Slither will never fail the CI pipeline. This effectively makes Slither a decorative check.

```yaml
- name: Run Slither
  uses: crytic/slither-action@v0.4.0
  continue-on-error: true
  with:
    target: contracts/
    slither-args: --filter-paths "lib/" --exclude-dependencies
```

**Recommendation**: Remove `continue-on-error: true` once initial Slither findings are triaged. Alternatively, use Slither's `--triage-mode` or `--sarif` output to manage findings without suppressing the check entirely.

---

### Finding 14 — CI Uses Nightly Foundry Toolchain

| Attribute | Value |
|-----------|-------|
| **Severity** | Informational |
| **File** | `.github/workflows/ci.yml` |
| **Lines** | 26 |

**Description**: The CI workflow uses `version: nightly` for the Foundry toolchain. Nightly builds may introduce regressions or behavior changes that break builds non-deterministically.

```yaml
- name: Install Foundry
  uses: foundry-rs/foundry-toolchain@v1
  with:
    version: nightly
```

**Recommendation**: Pin to a specific stable Foundry version for reproducible builds.

---

## PR #4: "Add EIP draft for Soulbound Equity Certificates"

**Commit**: `57caa2b23855982b8a1e689d5a06fb7bfcfe6389`
**Files**: `eip/eip-draft.md`

### Finding 15 — EIP Interfaces Not Implemented in Contract Code

| Attribute | Value |
|-----------|-------|
| **Severity** | Low |
| **File** | `eip/eip-draft.md` |
| **Lines** | Various |

**Description**: The EIP draft defines three formal interfaces (`IPactRegistry`, `IClaimCertificate`, `IStakeCertificate`) with specific function signatures and events. However, the reference implementation does not declare these interfaces or use `supportsInterface` for them. The EIP's standard interfaces table (Section 11.4 of the spec) lists IPactRegistry, IClaimCertificate, and IStakeCertificate with interface IDs as "TBD".

This means there is no way for on-chain consumers to detect protocol conformance via ERC-165 beyond the basic ERC-721 and ERC-5192 checks.

**Recommendation**: Define the interfaces as Solidity `interface` types, have contracts implement them, and register ERC-165 interface IDs.

---

### Finding 16 — EIP Draft Has No Security Issues

| Attribute | Value |
|-----------|-------|
| **Severity** | Informational |
| **File** | `eip/eip-draft.md` |

**Description**: The EIP draft is documentation only with no executable code changes. The Security Considerations section appropriately covers: authority compromise, front-running, content hash integrity, vesting clock manipulation, revocation scope, yield/staking restrictions, and legal enforceability limitations. No issues found in the document itself.

---

## PR #5: "Add verification guide for using protocol without app"

**Commit**: `4993c4f94b74c44181c3c3e0b0744299c1dc6515`
**Files**: `docs/VERIFY-WITHOUT-APP.md`, `scripts/verify-stake.sh`

### Finding 17 — Verification Script Does Not Validate Input Addresses

| Attribute | Value |
|-----------|-------|
| **Severity** | Low |
| **File** | `scripts/verify-stake.sh` |
| **Lines** | 15–23 |

**Description**: The shell script accepts a contract address and token ID as arguments but does not validate that the address is a valid Ethereum address format (0x followed by 40 hex characters). Malformed input is passed directly to `cast` commands.

```bash
STAKE_ADDRESS=$1
TOKEN_ID=$2
# No validation of address format
```

**Recommendation**: Add basic input validation for the Ethereum address format.

---

### Finding 18 — No Security Issues in Verification Documentation

| Attribute | Value |
|-----------|-------|
| **Severity** | Informational |
| **File** | `docs/VERIFY-WITHOUT-APP.md` |

**Description**: The verification guide correctly instructs users to verify certificate ownership and state using block explorers, `cast`, and JavaScript/TypeScript. It appropriately lists multiple public RPC endpoints and emphasizes that certificates exist independently of any application. No security issues, misinformation, or data leaks were found.

---

## Summary of Findings by PR

| PR | Critical | High | Medium | Low | Informational |
|----|----------|------|--------|-----|---------------|
| #1 | 0 | 1 | 3 | 3 | 0 |
| #2 | 0 | 0 | 0 | 1 | 2 |
| #3 | 0 | 0 | 1 | 0 | 1 |
| #4 | 0 | 0 | 0 | 1 | 1 |
| #5 | 0 | 0 | 0 | 1 | 1 |
| **Total** | **0** | **1** | **4** | **6** | **5** |

Note: Finding 1 (High) from PR #1 was resolved in PR #2.

## Key Recommendations

1. **Resolved**: The soulbound enforcement mechanism was correctly fixed in PR #2 using internal hook overrides.
2. **Implement role separation**: Separate `DEFAULT_ADMIN_ROLE` from `AUTHORITY_ROLE` and add timelocks for sensitive operations.
3. **Add emergency pause**: Implement OpenZeppelin's `Pausable` for critical functions.
4. **Align spec and implementation**: Either reduce the spec scope or expand the implementation to cover all specified fields.
5. **Fix CI pipeline**: Remove `continue-on-error` from Slither and pin Foundry version.
6. **Add `.env` to `.gitignore`**: Prevent accidental commitment of private keys.
7. **Implement ERC-165 for protocol interfaces**: Define and register `IPactRegistry`, `IClaimCertificate`, `IStakeCertificate` interface IDs.
8. **Expand test coverage**: Add fuzz tests for vesting, role management tests, and edge case coverage.
