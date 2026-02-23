# Security Audit Report — PRs #6 through #10

**Date**: 2026-02-23
**Auditor**: Automated Security Review (Cloud Agent)
**Scope**: Merge commits for PR #6–#10 in the Stake Protocol repository
**Method**: Full diff review of each merge commit against its first parent

---

## PR #6: Fix CI workflow to use default Foundry profile

**Merge Commit**: `8903d228ae3c8006cb85df5aab7cae5e400041ce`
**Files Changed**: `.github/workflows/ci.yml` (1 line)
**Change**: `FOUNDRY_PROFILE: ci` → `FOUNDRY_PROFILE: default`

### Findings

#### PR6-1: CI No Longer Uses a Dedicated Profile — Reduced Build Hardening

| Field | Value |
|-------|-------|
| Severity | Low |
| File | `.github/workflows/ci.yml`, line 10 |
| Category | CI/CD Configuration |

**Description**: The `ci` profile was removed in favor of `default`. A dedicated CI profile allows enabling stricter settings in CI (e.g., higher optimizer runs for gas checks, additional warnings-as-errors, or specific compiler flags) without affecting local development. By collapsing to `default`, the CI environment now runs with exactly the same settings as local development, removing the ability to enforce stricter CI-only constraints.

**Impact**: Low. This is a defensible simplification if the team does not need distinct CI settings. However, it means that any future need for CI-specific compiler flags will require re-introducing a separate profile.

**Recommendation**: Document the decision. If stricter CI settings are ever needed, re-add a `[profile.ci]` section to `foundry.toml`.

---

**PR #6 Summary**: 1 Low finding. No security vulnerabilities. The change is a legitimate simplification.

---

## PR #7: Apply forge fmt formatting to match CI style requirements

**Merge Commit**: `7d3e49656380737679a2cf6bed78af99627a5f96`
**Files Changed**: `contracts/src/StakeCertificates.sol`, `contracts/test/StakeCertificates.t.sol`
**Change**: Pure formatting — whitespace, line wrapping, brace style. No logic changes.

### Findings

**No security issues found.**

This PR is exclusively auto-formatting applied by `forge fmt`. Every change is whitespace-only: collapsing multi-line function signatures to single lines, removing braces from single-statement if blocks, adjusting comment alignment, etc. No logic, no variable names, no control flow, and no ABIs were modified.

I verified this by confirming:
- No new lines of Solidity logic were added or removed
- All changes are consistent with the `[profile.default.fmt]` settings in `foundry.toml` (line length 120, `single_line_statement_blocks = "single"`, `multiline_func_header = "all"`)
- Test file changes are also formatting-only

---

**PR #7 Summary**: No findings. Clean formatting PR.

---

## PR #8: Fix coverage command to handle stack-too-deep error

**Merge Commit**: `cbc4bba6ad7ec168a04e5845c5b4aa13069e3c39`
**Files Changed**: `.github/workflows/ci.yml` (1 line)
**Change**: `forge coverage --report summary` → `forge coverage --ir-minimum --report summary`

### Findings

#### PR8-1: `--ir-minimum` Reduces Coverage Accuracy

| Field | Value |
|-------|-------|
| Severity | Informational |
| File | `.github/workflows/ci.yml`, line 36 |
| Category | CI/CD Configuration |

**Description**: The `--ir-minimum` flag tells Forge to use the IR pipeline only for contracts that hit stack-too-deep errors under the legacy pipeline. This fixes the CI failure but produces coverage data from two different compilation pipelines in the same run. IR-compiled contracts may have different code paths than legacy-compiled ones, potentially causing minor inaccuracies in coverage line mapping.

**Impact**: Informational. This is the recommended workaround for stack-too-deep during coverage. The `via_ir = true` in `foundry.toml` already uses IR for production builds, so the coverage measurement is a reasonable approximation.

---

**PR #8 Summary**: 1 Informational finding. No security vulnerabilities. The change is the standard workaround for a known Foundry limitation.

---

## PR #9: Audit stake protocol

**Merge Commit**: `64a8f99118b4e212e899b1a1df216ed78e92a529`
**Files Changed**: `AUDIT.md` (new, 581 lines), `WHITEPAPER.md` (new, 485 lines)
**Change**: Added a full audit report and a whitepaper document.

### Findings

#### PR9-1: Audit Report Correctly Identifies Critical Smart Contract Bugs (Verified)

| Field | Value |
|-------|-------|
| Severity | Critical (in the underlying code — the audit report is correct) |
| File | `AUDIT.md` |
| Category | Audit Quality Verification |

**Description**: The AUDIT.md file identifies four Critical issues (C-1 through C-4) in the smart contracts. I independently verified these against the actual Solidity code at this commit:

**C-3 (Revocation does not reduce units) — VERIFIED CRITICAL**: `SoulboundStake.revokeStake()` (StakeCertificates.sol lines 530–556) only sets `s.revoked = true` but never modifies `s.units`. After revocation under `UNVESTED_ONLY` mode, the `units` field still reflects the original total. Any system reading `getStake()` will see incorrect ownership data.

**C-4 (Revoked stakes continue vesting) — VERIFIED CRITICAL**: `vestedUnits()` (StakeCertificates.sol lines 463–478) has no check for `s.revoked`. A revoked stake's vested amount continues increasing over time. This is a correctness bug: revoked equity should stop vesting at the moment of revocation.

**C-1 (No emergency pause) — VERIFIED CRITICAL**: No `Pausable` contract is inherited anywhere. There is no mechanism to halt operations if a vulnerability is discovered post-deployment.

**C-2 (Constructor deploys child contracts) — VERIFIED HIGH** (I would rate this High rather than Critical): The constructor (lines 599–601) deploys `StakePactRegistry`, `SoulboundClaim`, and `SoulboundStake` via `new`, making the initcode very large and preventing deterministic cross-chain deployment. This is a design concern, not a correctness bug.

#### PR9-2: Audit Report Lists High-Severity Issues — Independently Confirmed

| Field | Value |
|-------|-------|
| Severity | High (in the underlying code) |
| File | `AUDIT.md` |
| Category | Audit Quality Verification |

**Description**: The audit lists 8 High issues. Key ones I independently verified:

**H-1 (No UnitType stored on certificates) — VERIFIED**: The `UnitType` enum is defined (lines 45–50) but neither `ClaimState` (line 68) nor `StakeState` (line 77) includes a `unitType` field. The `issueClaim()` and `mintStake()` functions don't accept a `unitType` parameter. This is a real spec-to-implementation gap.

**H-6 (Partial redemption marks claim as fully redeemed) — VERIFIED**: In `redeemToStake()` (line 717), `units` can be less than `c.maxUnits`, but `markRedeemed()` (line 726) sets `c.redeemed = true` unconditionally. The remaining unredeemed units are lost.

**H-7 (No voidClaim revocation check) — VERIFIED**: `SoulboundClaim.voidClaim()` (line 395) checks `p.revocationMode == RevocationMode.NONE` and reverts. This means claims under `NONE`-mode pacts cannot be voided even though voiding is conceptually different from revocation.

#### PR9-3: WHITEPAPER.md Contains No Sensitive Data

| Field | Value |
|-------|-------|
| Severity | Informational |
| File | `WHITEPAPER.md` |
| Category | Data Leak Check |

**Description**: The whitepaper is a public-facing document with no private keys, API keys, internal URLs, or sensitive data. It describes the protocol design philosophy, lifecycle, transition mechanism, governance model, and Ethereum L1 deployment rationale. Content is appropriate for a public repository.

#### PR9-4: Whitepaper Gas Cost Estimates May Mislead

| Field | Value |
|-------|-------|
| Severity | Low |
| File | `WHITEPAPER.md`, Section X |
| Category | Documentation Accuracy |

**Description**: The whitepaper claims "the cost of operating a 50-person cap table on Ethereum L1 is approximately $27-53 for the full set of certificate operations." This assumes gas prices of 0.5–3 gwei. However, the AUDIT.md in the same PR calculates costs at 30 gwei as $2,500–$4,000 for a 50-person cap table. The whitepaper uses aggressively low gas price assumptions without disclaiming this. During periods of network congestion (>50 gwei), costs could exceed $10,000.

**Recommendation**: Add a clear disclaimer that costs are highly variable and provide a range at multiple gas price levels.

#### PR9-5: Whitepaper Describes Transition and Governance Not Yet Implemented

| Field | Value |
|-------|-------|
| Severity | Medium |
| File | `WHITEPAPER.md`, Sections VII–IX |
| Category | Spec-Implementation Discrepancy |

**Description**: The whitepaper describes in detail: a Vault mechanism, governance seat auctions, token holder override voting, Dutch auction price discovery, automated liquidity provisioning, and acquisition mechanics (Sections VII–IX). None of these features exist in the smart contract code. The whitepaper reads as a completed system description but the implementation only covers the pre-transition phase (Pact, Claim, Stake). There is no `transitioned` flag, no Vault, no ERC-20 token minting, no governance.

**Risk**: Users or investors reading the whitepaper may believe these features exist. The whitepaper should clearly mark unimplemented sections as "Planned" or "Future Work."

#### PR9-6: AUDIT.md Acknowledges Issues But Code Is Not Fixed in This PR

| Field | Value |
|-------|-------|
| Severity | Informational |
| File | `AUDIT.md` |
| Category | Process |

**Description**: PR #9 adds an audit report documenting serious bugs (C-3, C-4, H-6 etc.) but does not fix any of them. The bugs remain in the codebase at this commit. This is not inherently problematic — audits are typically separate from remediation — but it should be tracked.

---

**PR #9 Summary**: 2 Critical (confirming audit's own findings against code), 1 Medium, 1 Low, 2 Informational. The audit report itself is thorough and accurate. The whitepaper introduces documentation risk by describing unimplemented features.

---

## PR #10: Update spec v0.2: full lifecycle from certificates through transition

**Merge Commit**: `08b92c6d6d56be8d29077e0e7f00235aac14e49b`
**Files Changed**: `spec/STAKE-PROTOCOL.md` (568 insertions, 74 deletions)
**Change**: Major spec update from v0.1 to v0.2 adding Transition, Vault, Governance, Token Supply, and Acquisition sections.

### Findings

#### PR10-1: Spec v0.2 Mandates Revocation Snapshot — Implementation Does Not Comply

| Field | Value |
|-------|-------|
| Severity | Critical |
| File | `spec/STAKE-PROTOCOL.md`, §9.2 (new text around line 297) |
| Category | Spec-Implementation Discrepancy |

**Description**: The updated spec now explicitly mandates (using RFC 2119 "MUST"):

> "Snapshot the vested amount: set `units` to `vestedUnits` at the time of revocation."
> "Record the revoked quantity: set `revoked_units` to `totalUnits - vestedUnits`."
> "Record the revocation timestamp: set `revoked_at` to `block.timestamp`."
> "Halt further vesting: the `vestedUnits()` function MUST return the snapshot value for revoked stakes."

The implementation (`StakeCertificates.sol` lines 530–556) does none of this. The `StakeState` struct has no `revoked_units` or `revoked_at` fields. The `revokeStake()` function only sets `s.revoked = true`. The `vestedUnits()` function does not check the `revoked` flag.

The spec was updated to address the bugs found in the audit (PR #9), but the code was not updated to match. This creates a normative gap: the spec says "MUST" but the implementation does not comply.

#### PR10-2: Spec v0.2 Mandates `unit_type` on Certificates — Implementation Missing

| Field | Value |
|-------|-------|
| Severity | High |
| File | `spec/STAKE-PROTOCOL.md`, §6 (around line 172) |
| Category | Spec-Implementation Discrepancy |

**Description**: The updated spec states:

> "Conforming implementations MUST store the `unit_type` on each certificate (both Claims and Stakes)."

The implementation does not store `unit_type` on either `ClaimState` or `StakeState`. The `UnitType` enum exists (line 45) but is unused. Neither `issueClaim()` nor `mintStake()` accept a `unitType` parameter.

#### PR10-3: Spec v0.2 Mandates Emergency Pause — Implementation Missing

| Field | Value |
|-------|-------|
| Severity | High |
| File | `spec/STAKE-PROTOCOL.md`, §20.5 |
| Category | Spec-Implementation Discrepancy |

**Description**: The updated spec states:

> "Conforming implementations MUST implement an emergency pause mechanism. When paused, all state-changing functions MUST revert."

No pause mechanism exists in the implementation.

#### PR10-4: Spec v0.2 Defines IStakeVault and IStakeToken Interfaces — Not Implemented

| Field | Value |
|-------|-------|
| Severity | Medium |
| File | `spec/STAKE-PROTOCOL.md`, §11.4, §11.5 |
| Category | Spec-Implementation Discrepancy |

**Description**: The spec defines `IStakeVault` with 10 functions (initializeFromTransition, claimTokens, bidForSeat, reclaimSeat, initiateOverride, voteOverride, executeOverride, etc.) and `IStakeToken` with 5 functions. No implementation of either interface exists in the codebase. The spec references these as normative ("A conforming implementation of the Vault MUST support...") but the reference implementation section (§18) acknowledges these are future work.

#### PR10-5: Spec v0.2 Transition Gas Estimates May Exceed Block Limit for Large Cap Tables

| Field | Value |
|-------|-------|
| Severity | Medium |
| File | `spec/STAKE-PROTOCOL.md`, §12.2 |
| Category | Protocol Design |

**Description**: The spec estimates ~130,000 gas per certificate during transition, and states "A 50-person cap table transitions in a single transaction for approximately 6.5 million gas, well within Ethereum's 30 million gas block limit." It also adds: "For cap tables exceeding approximately 200 holders, the transition MUST support batched execution."

However, the 130K per-certificate estimate is likely optimistic. The spec calls for 5 operations per certificate (unlock, transfer, mint ERC-20, record lockup, set flag). On Ethereum L1, a `safeTransferFrom` of an ERC-721 alone is ~60-80K gas. Minting ERC-20 tokens is ~50K. The real per-certificate cost is likely 150-200K gas, reducing the single-transaction limit to ~150-200 holders (not 230).

More importantly, the batched execution path introduces state management complexity: partial transitions must handle the case where some certificates are transitioned and others are not, which creates a mixed state that the current contract design does not support.

#### PR10-6: Spec v0.2 Governance Override Quorum May Be Insufficient

| Field | Value |
|-------|-------|
| Severity | Medium |
| File | `spec/STAKE-PROTOCOL.md`, §15.7 |
| Category | Protocol Design |

**Description**: The token holder override mechanism requires 50%+1 of votes cast with only 20% quorum. This means that in theory, just 10.01% of total token supply (50%+1 of 20% quorum) could replace all governors. For a project with concentrated token holdings (common in early post-transition), a single whale could execute an override.

The spec does include a 90-day cooldown between overrides, but this does not prevent the initial capture. A hostile actor acquiring ~10% of tokens could execute an override, install friendly governors, and then use those governors to issue favorable decisions during the 90-day cooldown.

#### PR10-7: Spec v0.2 ERC-165 Interface IDs Remain TBD

| Field | Value |
|-------|-------|
| Severity | Low |
| File | `spec/STAKE-PROTOCOL.md`, §11.6 |
| Category | Incomplete Specification |

**Description**: All six interface IDs (`IPactRegistry`, `IClaimCertificate`, `IStakeCertificate`, `IStakeVault`, `IStakeToken`) are still listed as "TBD". For a v0.2 spec, this is acceptable, but they must be computed before any deployment claims ERC-165 compliance.

#### PR10-8: Spec v0.2 Adds `PRO_LOCKUP` Parameter Change Without Migration Note

| Field | Value |
|-------|-------|
| Severity | Low |
| File | `spec/STAKE-PROTOCOL.md`, §5.4 |
| Category | Backward Compatibility |

**Description**: The clause registry changes `PRO_LOCKUP` params from `until_ts` (an absolute timestamp) to `lockup_days` (a relative duration). Any tooling, indexer, or off-chain system that parsed the v0.1 format (`until_ts`) would break when encountering v0.2 Pacts using `lockup_days`. The spec provides no migration guidance or versioning signal for clause parameter schemas.

#### PR10-9: Spec v0.2 Claims Transition Is Atomic But Describes Multi-Tx Batching

| Field | Value |
|-------|-------|
| Severity | Low |
| File | `spec/STAKE-PROTOCOL.md`, §4.5 and §12.2 |
| Category | Specification Inconsistency |

**Description**: Section 4.5 states changes take effect "atomically" but section 12.2 introduces batched execution for large cap tables. These are contradictory: a multi-transaction batch is by definition not atomic. If the issuer's transaction fails between batches, the system is in a partially-transitioned state where some certificates are in the Vault and some are still soulbound, creating inconsistencies in governance weight calculations and token claims.

The spec should define the invariants that must hold during partial transition and specify how the system behaves in this intermediate state.

#### PR10-10: Spec v0.2 Dutch Auction Lacks Oracle/Manipulation Protections

| Field | Value |
|-------|-------|
| Severity | Medium |
| File | `spec/STAKE-PROTOCOL.md`, §12.5 |
| Category | Protocol Design |

**Description**: The price discovery mechanism (Dutch auction for public offering) is described but lacks protections against manipulation. Specifically:
- No minimum participation thresholds (a single bidder could buy the entire public offering at the floor price)
- No anti-sybil measures (a single entity bidding through multiple addresses)
- No circuit breakers if the auction clearing price is suspiciously low

For an equity system where the clearing price may set precedent for valuation, this is a meaningful gap.

---

**PR #10 Summary**: 1 Critical, 2 High, 4 Medium, 3 Low. The spec update is comprehensive and addresses many issues raised in the audit, but the code was not updated to match the new spec requirements. The newly specified transition and governance mechanisms introduce several design-level concerns that should be resolved before implementation begins.

---

## Cross-PR Summary Table

| PR | Critical | High | Medium | Low | Informational | Total |
|----|----------|------|--------|-----|---------------|-------|
| #6 | 0 | 0 | 0 | 1 | 0 | 1 |
| #7 | 0 | 0 | 0 | 0 | 0 | 0 |
| #8 | 0 | 0 | 0 | 0 | 1 | 1 |
| #9 | 2* | 0 | 1 | 1 | 2 | 6 |
| #10 | 1 | 2 | 4 | 3 | 0 | 10 |
| **Total** | **3** | **2** | **5** | **5** | **3** | **18** |

*\* PR #9's Critical findings are confirmations that the audit report (AUDIT.md) accurately identifies real bugs in the existing code.*

## Key Takeaways

1. **The most important finding across all 5 PRs**: The smart contract revocation logic is broken (confirmed in PR #9 audit, mandated fixed in PR #10 spec, but never actually fixed in code). `revokeStake()` sets a boolean flag but doesn't snapshot vested units, reduce total units, or halt further vesting. This is a correctness bug that would cause incorrect equity accounting in production.

2. **Spec-implementation divergence is growing**: PR #10 updated the spec to require features (emergency pause, unit_type storage, revocation snapshots) that the implementation does not provide. Each PR widens the gap rather than closing it.

3. **No data leaks found**: No private keys, API keys, secrets, or sensitive data were found in any PR.

4. **No reentrancy or overflow vulnerabilities found**: The contracts use OpenZeppelin v5, Solidity 0.8.24 (built-in overflow protection), and all external calls go to known, deployer-owned contracts. The soulbound enforcement is correctly implemented via `_update`, `_approve`, and `_setApprovalForAll` overrides.

5. **CI pipeline has soft-fail issues**: Slither runs with `continue-on-error: true` (never blocks CI), and gas snapshots use `|| forge snapshot` (auto-regenerate on failure). Neither provides meaningful protection against regressions.

---

*End of audit report.*
