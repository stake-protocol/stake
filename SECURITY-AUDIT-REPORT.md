# Stake Protocol — Security & Consistency Audit Report

**Date**: 2026-02-23
**Scope**: All documentation files and Solidity smart contracts
**Auditor**: Automated cross-reference and security analysis

---

## Executive Summary

The Stake Protocol codebase contains a **fundamental architectural divergence** between the documentation and the implementation. The smart contracts implement a "vesting on Claims, Stakes are unconditional" model (consistent with `DESIGN.md`), while the protocol specification (`STAKE-PROTOCOL.md`), the EIP draft (`eip-draft.md`), the whitepaper (`WHITEPAPER.md`), the audit report (`AUDIT.md`), the verification guide (`VERIFY-WITHOUT-APP.md`), and the README (`README.md`) all describe a "vesting on Stakes with revocation" model. This means **7 out of 9 documentation files describe a system that does not match the deployed contracts**.

Additionally, the audit report (`AUDIT.md`) appears to have been conducted on an older version of the code, and every critical/high finding it reports has been fixed in the current contracts — yet the report is presented as current and its "Spec-to-Implementation Gap Summary" is completely wrong for the current state.

### Severity Summary

| Severity | Count |
|---|---:|
| Critical | 3 |
| High | 8 |
| Medium | 10 |
| Low | 7 |
| Informational | 7 |

---

## CRITICAL FINDINGS

### C-1: Fundamental Architecture Contradiction — Vesting Lives on Claims in Code but on Stakes in Spec/EIP/Whitepaper

**Documents**: `STAKE-PROTOCOL.md` §6.4, §9.2, §11.3, §12.2 / `eip-draft.md` StakeState struct / `WHITEPAPER.md` §V.C / `DESIGN.md` Decision 3 / Actual code (`StakeCertificates.sol`)

**Severity**: Critical

**What's wrong**: The most fundamental design question — where does vesting live? — is answered differently across documents:

| Source | Where vesting lives | Stakes revocable? |
|---|---|---|
| `DESIGN.md` (Decision 3, 4) | Claims only | No — "once a Claim is redeemed to a Stake, no one can revoke or void that Stake" |
| **Actual Code** | **Claims only** (`ClaimState` has `vestStart/vestCliff/vestEnd/revokedAt`; `StakeState` has none) | **No** — `SoulboundStake` has no revoke function |
| `STAKE-PROTOCOL.md` §6.4 | Stakes (`vestStart`, `vestCliff`, `vestEnd`, `revokedAt`, `revokedUnits` on StakeState) | Yes — §9.2 describes three revocation modes |
| `eip-draft.md` | Stakes (StakeState struct has `vestStart`, `vestCliff`, `vestEnd`, `revocableUnvested`) | Yes — has `revokeStake` in IStakeCertificate |
| `WHITEPAPER.md` §V.C | Stakes ("A hash of the vesting schedule payload") | Implied yes via §V.C |
| `AUDIT.md` C-1 | Stakes (reports vesting bug on `SoulboundStake.revokeStake`) | Yes |

The **code** and **DESIGN.md** agree on the current architecture. Every other document describes an obsolete design. This means the protocol specification, the EIP, the whitepaper, and the audit report are all **materially wrong** about the core data model.

**Why it matters**: Anyone implementing from the spec or EIP will build an incompatible system. Anyone reading the whitepaper will have incorrect expectations about how ownership works. The audit report is diagnosing bugs in code that no longer exists.

---

### C-2: Audit Report (`AUDIT.md`) is Completely Outdated and Misleading

**Document**: `AUDIT.md`

**Severity**: Critical

**What's wrong**: The audit report claims to review the current codebase ("Local working tree (pre-commit)") but every major finding has been fixed in the current code:

| Audit Finding | Audit Claim | Current Code Reality |
|---|---|---|
| **C-1**: Revocation doesn't snapshot vested units on Stakes | Bug on `SoulboundStake.revokeStake` | Stakes have NO revocation. Vesting/revocation are on Claims. Claims properly snapshot via `revokedAt` timestamp (line 547, 609). |
| **H-1**: Partial redemption discards remaining units | `markRedeemed` marks fully redeemed | `recordRedemption` properly tracks `redeemedUnits`, supports partial redemption (line 574). |
| **H-2**: `unit_type` not stored on-chain | `ClaimState`/`StakeState` omit it | Both `ClaimState` (line 84) and `StakeState` (line 93) have `UnitType unitType`. |
| **H-3**: Base URI cannot be set | No forwarding function on StakeCertificates | `setClaimBaseURI` (line 814) and `setStakeBaseURI` (line 819) exist. `BaseURIUpdated` event emitted (line 153). |
| **H-4**: Authority cannot be rotated | Immutable authority | `transferAuthority(address newAuthority)` exists (line 792). |
| **M-1**: Claims can't be voided when revocation disabled | `voidClaim` checks revocationMode | `voidClaim` works regardless of revocationMode (line 505). |
| **M-3**: No batch issuance | Only single-item operations | `issueClaimBatch` exists (line 940). |
| **L-1**: No event emitted on base URI change | Missing event | `BaseURIUpdated` event emitted (line 153). |
| **L-4**: `getPact()` always reverts | No `tryGetPact` | `tryGetPact` exists (line 283). |

The "Spec-to-Implementation Gap Summary" table at the end of the audit is also entirely wrong for the current code. It claims `unit_type` is not implemented (it is), claims transition/vault are not implemented (they are in `StakeVault.sol` and `StakeToken.sol`).

**Why it matters**: Publishing a stale audit report that claims to cover the current code is dangerous. It gives a false sense of security (readers think issues were found and should be fixed) while real issues in the current code go unmentioned. It also creates liability risk — anyone relying on this audit would be misled.

---

### C-3: No Snapshot Mechanism for Override Voting — Flash Loan / Token Transfer Attack Vector

**Documents**: `STAKE-PROTOCOL.md` §21.6, `StakeVault.sol` lines 416-431

**Severity**: Critical

**What's wrong**: The spec explicitly identifies flash loan governance attacks as a threat vector and says "Override votes SHOULD use a snapshot mechanism where voting power is determined at proposal creation, not at vote time" (§21.6). The code does NOT implement snapshots — `voteOverride()` reads `token.governanceBalance(msg.sender)` at the time of the vote (line 422), not at proposal creation time.

This means:
1. A voter can vote with tokens, transfer them to another address, and vote again from that address.
2. A flash loan attack is partially possible: borrow tokens, vote, return tokens (though the 14-day voting period limits pure flash loans, accumulated token movement across the period is still exploitable).
3. Token holders can double-count their votes by transferring tokens between addresses during the voting period.

**Why it matters**: The override is the "nuclear option" that replaces all governors. If the voting mechanism is manipulable, an attacker could execute an override with less than the intended threshold of support, seizing governance control.

---

## HIGH FINDINGS

### H-1: Spec Interface `IStakeCertificates` Does Not Match Code

**Documents**: `STAKE-PROTOCOL.md` §11.4 vs `StakeCertificates.sol`

**Severity**: High

**What's wrong**: The spec's `IStakeCertificates` interface (§11.4) differs from the code in multiple ways:

| Spec Function | Code Function |
|---|---|
| `redeemToStake(bytes32 redemptionId, uint256 claimId, uint256 units, UnitType unitType, uint64 vestStart, uint64 vestCliff, uint64 vestEnd, bytes32 reasonHash)` | `redeemToStake(bytes32 redemptionId, uint256 claimId, uint256 units, bytes32 reasonHash)` — no vesting params, no unitType |
| `revokeStake(uint256 stakeId, bytes32 reasonHash)` | Does not exist. Has `revokeClaim(bytes32 issuanceId, bytes32 reasonHash)` instead |
| `createPact(... bool defaultRevocableUnvested)` | `createPact(... RevocationMode revocationMode)` — no `defaultRevocableUnvested` param |
| `issueClaim(... uint64 redeemableAt)` | `issueClaim(... uint64 redeemableAt, uint64 vestStart, uint64 vestCliff, uint64 vestEnd)` — extra vesting params |

Additionally, the code has `revokeClaim` which is not in the spec interface at all.

---

### H-2: Spec `IStakeVault` Interface Does Not Match Code

**Documents**: `STAKE-PROTOCOL.md` §11.5 vs `StakeVault.sol`

**Severity**: High

**What's wrong**:

| Spec Function | Code Reality |
|---|---|
| `processTransitionBatch(uint256[] stakeIds, address liquidationRouter)` | `processTransitionBatch(uint256[] stakeIds)` — no liquidationRouter param. Router is set separately via `deployLiquidator()`. |
| `releaseVestedTokens(uint256 stakeId)` | Does not exist. Not needed because Stakes are unconditional (no vesting). |
| `claimTokens()` | Exists and matches. |

The spec describes a vault that tracks ongoing vesting schedules and releases tokens incrementally (§13.3). The code does a simple 1:1 token mint because Stakes have no vesting. The entire vesting-at-transition model described in the spec does not exist in the code.

---

### H-3: Verification Guide (`VERIFY-WITHOUT-APP.md`) Has Completely Wrong ABI Signatures

**Document**: `VERIFY-WITHOUT-APP.md`

**Severity**: High

**What's wrong**: The guide provides incorrect struct signatures that will fail when used:

**ClaimState in guide** (line 41):
```
Returns: (voided, redeemed, issuedAt, redeemableAt, maxUnits, reasonHash)
```

**Actual ClaimState** (code line 76-88):
```
(voided, issuedAt, redeemableAt, vestStart, vestCliff, vestEnd, revokedAt, unitType, maxUnits, redeemedUnits, reasonHash)
```

**StakeState in guide** (line 47):
```
Returns: (revoked, issuedAt, vestStart, vestCliff, vestEnd, revocableUnvested, units, reasonHash)
```

**Actual StakeState** (code line 90-95):
```
(issuedAt, unitType, units, reasonHash)
```

The cast commands (lines 87-90), JavaScript ABIs (lines 120-126), and "What Each Field Means" tables (lines 200-220) are all wrong. Anyone following this guide to verify their ownership will get decode errors or incorrect data.

---

### H-4: README Code Example Has Wrong Function Signature

**Document**: `README.md` lines 113-123

**Severity**: High

**What's wrong**: The README example for `redeemToStake` shows:
```solidity
uint256 stakeId = certificates.redeemToStake(
    redemptionId,
    claimId,
    1000,             // units
    vestStart,
    vestCliff,
    vestEnd,
    bytes32(0)        // reasonHash
);
```

The actual function signature is:
```solidity
function redeemToStake(
    bytes32 redemptionId,
    uint256 claimId,
    uint256 units,
    bytes32 reasonHash
)
```

The example passes vesting parameters that the function doesn't accept. Additionally, the README's `issueClaim` example (lines 105-111) is missing the `vestStart`, `vestCliff`, `vestEnd` parameters that the actual function requires.

---

### H-5: `setAuthorizedSupply` Allows Decrease, Contradicting Spec

**Documents**: `STAKE-PROTOCOL.md` §14.2 vs `StakeToken.sol` line 96

**Severity**: High

**What's wrong**: The spec says: "The `authorizedSupply` is set at transition and MAY only be **increased** by a token holder supermajority vote" (§14.2, emphasis added). The code allows both increase AND decrease:

```solidity
function setAuthorizedSupply(uint256 newSupply) external onlyRole(GOVERNANCE_ROLE) {
    if (newSupply < totalSupply()) revert InvalidSupply();  // Only checks vs totalSupply, not vs current authorizedSupply
    ...
}
```

This allows governance to reduce the authorized supply down to `totalSupply()`. While this can't destroy existing tokens, it eliminates reserved/unissued supply, which could be used as an attack by governors to prevent future legitimate issuance (e.g., employee compensation, capital raises).

---

### H-6: No Annual Issuance Tracking — 20% Rule Not Enforced

**Documents**: `STAKE-PROTOCOL.md` §14.3 vs `StakeToken.sol`

**Severity**: High

**What's wrong**: The spec requires (§14.3): "Governance MUST track cumulative issuance within each annual period" with a 20% threshold separating governance approval from token holder approval. The `StakeToken` contract has NO tracking of:
- Annual issuance amounts
- Annual period start/end dates
- Different approval thresholds for <= 20% vs > 20%

The `governanceMint` function (line 109) simply checks if the total supply would exceed authorized supply. There is no enforcement of the annual issuance limit.

---

### H-7: No Staggered Governance Seat Terms at Transition

**Documents**: `STAKE-PROTOCOL.md` §15.2 vs `StakeVault.sol`

**Severity**: High

**What's wrong**: The spec requires (§15.2): "At transition, seats MUST be assigned staggered initial term expiry dates. For N seats with term length T, the i-th seat expires at transitionTimestamp + (T * (i + 1)) / N. This ensures governance continuity — the entire governance body never turns over simultaneously."

The vault code does NOT assign any terms at transition. Governance seats are only assigned terms when they are individually auctioned via `settleAuction()`. This means all initial auctions could happen simultaneously, and all initial terms could expire simultaneously — exactly the scenario the spec says MUST be prevented.

---

### H-8: EIP Draft Status Flags Contradict Spec

**Documents**: `eip-draft.md` vs `STAKE-PROTOCOL.md` §6.2

**Severity**: High

**What's wrong**: The EIP draft defines status as a `uint32` bitfield:
```
| Bit | Name | Description |
| 0 | VOIDED | Certificate has been voided |
| 1 | REVOKED | Stake has been revoked |
| 2 | REDEEMED | Claim has been converted |
```

The spec explicitly rejects this approach (§6.2): "Certificate status is tracked via **individual boolean fields** on each certificate struct, **not a bitfield**. This keeps the storage layout simple and avoids bitwise operations in the EVM."

The code agrees with the spec (uses individual booleans). The EIP contradicts both.

Additionally, the EIP's `ClaimState` struct has a single `bool redeemed` while both the spec and code use `redeemedUnits`/`fullyRedeemed` to support partial redemption.

---

## MEDIUM FINDINGS

### M-1: Whitepaper Claims Pact is "Immutable" — Misleading

**Document**: `thesis.md` line 18

**Severity**: Medium

**Specific text**: "A Pact, or Plain Agreement for Contract Terms, is an **immutable** onchain agreement that lets founders issue equity..."

**What's wrong**: Pacts CAN be mutable. The `mutablePact` flag on the Pact struct controls whether amendments are allowed. Calling all Pacts "immutable" is misleading to potential users/investors. The spec correctly describes this as optional (`STAKE-PROTOCOL.md` §5.1: "A Pact MAY be declared mutable or immutable").

---

### M-2: Whitepaper Gas Estimates Don't Match Spec

**Documents**: `WHITEPAPER.md` §VII.B vs `STAKE-PROTOCOL.md` §12.2

**Severity**: Medium

| Estimate | Whitepaper | Spec |
|---|---|---|
| Gas per certificate at transition | ~130,000 | ~150,000 |
| 50-person cap table total gas | ~6.5 million | ~7.5 million |
| Cost estimate | "$15-60" | Not specified (spec just says "well within 30M limit") |

These inconsistencies undermine credibility. The code does 1:1 unconditional token minting (simpler than either document describes), so the actual gas would differ from both estimates.

---

### M-3: Pact Struct Missing `defaultRevocableUnvested` Field

**Documents**: `STAKE-PROTOCOL.md` §5.2.1 vs `StakeCertificates.sol` line 63

**Severity**: Medium

**What's wrong**: The spec defines `defaultRevocableUnvested: bool` as an onchain Pact field. The code's `Pact` struct does not have this field. The spec's `createPact` interface (§11.1) includes it as a parameter. The code's `createPact` (on both `StakePactRegistry` and `StakeCertificates`) does not accept it.

Since the current architecture has no revocation on Stakes, this field would be meaningless anyway — but the spec still lists it, and the spec interface includes it.

---

### M-4: Spec `remainingUnits` Definition Differs from Code

**Documents**: `STAKE-PROTOCOL.md` §11.2 vs `SoulboundClaim` line 583

**Severity**: Medium

**What's wrong**: The spec says `remainingUnits` returns `maxUnits - redeemedUnits` (§11.2). The code returns `vestedUnits - redeemedUnits` (line 588-589), which can be LESS than `maxUnits - redeemedUnits` if not all units have vested yet. This is actually more correct for the current architecture (where vesting is on Claims), but it's a behavioral difference from the spec.

---

### M-5: Spec Clause ID `PWR_BOARD` vs Design Doc `PWR_BOARD_SEAT`

**Documents**: `STAKE-PROTOCOL.md` §5.4 vs `DESIGN.md` §21.1.1

**Severity**: Medium

**What's wrong**: The spec's clause registry uses `PWR_BOARD` (§5.4). The design document's §21.1.1 refers to `PWR_BOARD_SEAT`. The whitepaper §VI.A uses `PWR_BOARD_SEAT` and `PWR_OFFICER`. These are supposed to be canonical identifiers — inconsistent naming prevents interoperability.

---

### M-6: Protocol Fee Liquidator Has No Slippage Protection

**Document**: `ProtocolFeeLiquidator.sol` line 156

**Severity**: Medium

**What's wrong**: The `liquidate()` function calls the router with no minimum output amount:
```solidity
proceeds = ILiquidationRouter(router).liquidate(token, tokensSold, treasury);
```

There is no check that `proceeds >= minExpected`. A sandwich attack could extract significant value from each liquidation. While the spec describes this as "permissionless" and "deterministic," the lack of slippage protection means the proceeds are NOT deterministic — they depend on pool state, which is manipulable.

---

### M-7: Whitepaper Transition Description Says "Single Batch" — Code Supports Multiple

**Documents**: `WHITEPAPER.md` §VII.B vs `StakeVault.sol` line 184

**Severity**: Medium

**Specific text** (Whitepaper): "all certificates are programmatically transferred to the vault **in a single batch operation**"

**What's wrong**: The code's `processTransitionBatch` is designed to be called multiple times with different sets of stakeIds. The spec correctly describes this (§12.2: "This can be batched across multiple transactions"). The whitepaper's "single batch" claim is incorrect.

---

### M-8: Whitepaper Says No Admin Override for Soulbound Transfers — Code Has Vault Bypass

**Document**: `WHITEPAPER.md` §V.D

**Severity**: Medium

**Specific text**: "This is not a soft restriction. There is no 'emergency unlock.' There is no admin override that lets the issuer transfer someone's certificate to another wallet."

**What's wrong**: The code DOES have an override — the vault contract can transfer certificates regardless of soulbound status (line 196: `if (auth != _vault) revert Soulbound()`). While the spec correctly documents this (§6.5.1), the whitepaper's absolute claim of "no admin override" is misleading. The vault is functionally an admin that can forcibly transfer certificates, even if it's code-controlled rather than EOA-controlled.

---

### M-9: Design Decision 11 Misdescribes Fee Basis

**Document**: `DESIGN.md` Decision 11

**Severity**: Medium

**Specific text**: "a 1% fee is assessed on **total token supply**"

**What's wrong**: The code assesses 1% on tokens minted per batch for certificate holders (line 235: `uint256 protocolFee = (totalMinted * PROTOCOL_FEE_BPS) / BPS_BASE`), not on total token supply. The spec correctly describes this (§18.1): "Calculate the total tokens minted for certificate holders **in that batch**." The difference matters: if authorized supply is 100M but only 60M is minted for certificate holders, the fee is 1% of 60M (600K), not 1% of 100M (1M).

---

### M-10: Auction Minimum Bid Semantics Unclear Across Unit Types

**Documents**: `StakeVault.sol` line 324 / `STAKE-PROTOCOL.md` §15.3

**Severity**: Medium

**What's wrong**: The minimum bid is calculated as `(s.units * auctionMinBidBps) / BPS_BASE`. The `units` field's meaning depends on `unitType` (SHARES, BPS, WEI, CUSTOM). If a stake has 500 BPS units (= 5% ownership), the minimum bid would be 50 tokens. If a stake has 50,000 SHARES units, the minimum bid would be 5,000 tokens. These produce wildly different economic results. The spec doesn't address how minimum bids should work across different unit types.

---

## LOW FINDINGS

### L-1: EIP Draft Missing Clauses from Spec Registry

**Documents**: `eip-draft.md` vs `STAKE-PROTOCOL.md` §5.4

**Severity**: Low

**What's wrong**: The EIP's "Standard Clause Registry" is missing 6 clauses that appear in the spec:
- `PWR_DELEGATE` (delegation policy)
- `PRI_CONVERT` (conversion behavior)
- `PRO_APPROVALS` (protective provisions)
- `PRO_MFN` (MFN upgrades)
- `PRO_PREEMPTIVE` (preemptive rights)
- `PRO_LOCKUP` (transfer lockup)

---

### L-2: README Repository Structure is Incomplete

**Document**: `README.md` lines 27-34

**Severity**: Low

**What's wrong**: The repository structure shows only `StakeCertificates.sol`. It does not mention `StakeToken.sol`, `StakeVault.sol`, `StakeBoard.sol`, or `ProtocolFeeLiquidator.sol`, which are all part of the protocol.

---

### L-3: Security Policy Says "Not Audited" Despite Having an Audit Report

**Documents**: `SECURITY.md` line 46 vs `AUDIT.md`

**Severity**: Low

**Specific text** (SECURITY.md): "The reference implementation is provided for educational purposes and has **not been audited**."

**What's wrong**: An audit report exists (`AUDIT.md`). Either the security policy should reference it, or the audit report should be clearly labeled as a self-audit / internal review rather than an external audit. The contradiction creates confusion about the security posture.

---

### L-4: StakeBoard Has No Target Validation

**Document**: `StakeBoard.sol` line 24

**Severity**: Low

**What's wrong**: The board accepts any `target_` address in the constructor. There is no validation that the target is actually a `StakeCertificates` contract, or that this board is set as the authority on that contract. A misconfigured board could execute proposals against the wrong contract, or proposals could fail silently because the board isn't the authority.

---

### L-5: Override Proposal Can Be Created When No Active Governance Seats Exist

**Document**: `StakeVault.sol` line 401

**Severity**: Low

**What's wrong**: `proposeOverride()` doesn't check if any governance seats are currently active. If there are no active seats, executing the override is a no-op that wastes gas and triggers the 90-day cooldown, blocking legitimate future overrides.

---

### L-6: StakeBoard Cancel Uses Wrong Error

**Document**: `StakeBoard.sol` line 259

**Severity**: Low

**What's wrong**: `cancel()` checks `msg.sender != p.proposer` and reverts with `NotMember()`. The error should be something like `NotProposer()` — the caller might be a member but not the proposer. Using `NotMember()` is misleading.

---

### L-7: Dangling Token Approval in ProtocolFeeLiquidator

**Document**: `ProtocolFeeLiquidator.sol` line 153

**Severity**: Low

**What's wrong**: `liquidate()` approves the router for `tokensSold` tokens, then calls the router. If the router doesn't consume the full approval (e.g., partial fill, router bug), a dangling approval remains. Should use `approve(router, 0)` after the swap, or use `safeIncreaseAllowance`.

---

## INFORMATIONAL FINDINGS

### I-1: Spec Reference [9] in thesis.md Points to Wrong Source

**Document**: `thesis.md` line 28

**Severity**: Informational

**Specific text**: "For context, traditional IPO underwriters charge 4–7% of gross proceeds[9]."

**What's wrong**: The references section lists `[5]` for IPO fees, not `[9]`. Reference `[9]` doesn't exist in the sources list. The references section only goes to `[5]`.

---

### I-2: Spec Describes Governance Seat Reclaim as Opening New Auction — Code Doesn't

**Document**: `STAKE-PROTOCOL.md` §15.5 vs `StakeVault.sol` line 375

**Severity**: Informational

**What's wrong**: Spec §15.5 says `reclaimSeat` "Opens a new auction for the seat" (point 4). The code's `reclaimSeat()` only returns the certificate to the vault and returns bid tokens — it does NOT automatically start a new auction. A separate `startSeatAuction()` call is required.

---

### I-3: Spec References `burnStake` in Decision 5 But Code Names It `burn`

**Documents**: `DESIGN.md` Decision 5 vs `SoulboundStake.sol` line 699

**Severity**: Informational

**What's wrong**: DESIGN.md references `burnStake()` as the function name. The code names it simply `burn()`. Minor naming inconsistency.

---

### I-4: Spec's IClaimCertificate Interface Differs from Code's SoulboundClaim

**Documents**: `STAKE-PROTOCOL.md` §11.2 vs `SoulboundClaim`

**Severity**: Informational

**What's wrong**: The spec interface has `recordRedemption(uint256 claimId, uint256 units, bytes32 reasonHash)` which matches the code. But the spec interface does NOT include `revokeClaim()`, `vestedUnits()`, `unvestedUnits()`, or `redeemableUnits()` — all of which exist in the code. The spec's claim interface is incomplete for the current architecture where vesting/revocation are on claims.

---

### I-5: DESIGN.md Incorrectly States Claim Has "revoked" and "disputed" Status Flags

**Document**: `DESIGN.md` Decision 10, line 160

**Severity**: Informational

**Specific text** (V.B): "Status flags (voided, revoked, redeemed, disputed)"

**What's wrong**: The whitepaper lists `disputed` as a Claim status flag. Neither the spec, the code, nor any other document implements a `DISPUTED` status. The `revoked` status on claims is represented via `revokedAt != 0` rather than a boolean flag.

---

### I-6: Spec §21.1.1 Uses `PWR_BOARD_SEAT` While §5.4 Uses `PWR_BOARD`

**Document**: `STAKE-PROTOCOL.md` §21.1.1 vs §5.4

**Severity**: Informational

**What's wrong**: §5.4's clause registry lists `PWR_BOARD` with description "Board seat or appointment right". §21.1.1 refers to board seats as `PWR_BOARD_SEAT` clause. These should use the same canonical identifier.

---

### I-7: DESIGN.md References `PWR_OFFICER` Clause Not in Spec Registry

**Document**: `WHITEPAPER.md` §VI.A

**Severity**: Informational

**Specific text**: "Board seats and officer roles are recorded in Pacts as rights clauses (`PWR_BOARD_SEAT`, `PWR_OFFICER`)"

**What's wrong**: `PWR_OFFICER` does not appear in the spec's clause registry (§5.4). It's referenced in the whitepaper but never defined.

---

## Summary of Cross-Document Contradictions

| Topic | STAKE-PROTOCOL.md | WHITEPAPER.md | DESIGN.md | eip-draft.md | AUDIT.md | Code |
|---|---|---|---|---|---|---|
| Vesting location | Stakes | Stakes | **Claims** | Stakes | Stakes | **Claims** |
| Stake revocable? | Yes | Implied | **No** | Yes | Yes (buggy) | **No** |
| Claim revocable? | Only voided | Only voided | **Yes (3 modes)** | Only voided | — | **Yes (3 modes)** |
| Status storage | Booleans | — | — | Bitfield | — | **Booleans** |
| Partial redemption | Yes (§11.2) | — | — | No (single bool) | Broken (H-1) | **Yes** |
| Protocol fee basis | Per-batch minted | Total minted | Total supply | — | — | **Per-batch minted** |
| Gas per cert (transition) | ~150K | ~130K | — | — | — | **N/A (unconditional)** |
| Batch transition | Multiple txns | Single batch | — | — | — | **Multiple txns** |
| Vault has releaseVestedTokens | Yes | — | — | — | — | **No (not needed)** |

---

## Recommendations (Prioritized)

### Must-Fix Before Any Release

1. **Update all documentation to match the current "vesting on Claims, Stakes unconditional" architecture.** The spec, EIP, whitepaper, and all supporting documents must reflect the code. (C-1)
2. **Either remove or clearly label the audit report as outdated**, or conduct a new audit against the current code. (C-2)
3. **Implement voting snapshots for override proposals** to prevent double-voting and token movement attacks. (C-3)
4. **Fix VERIFY-WITHOUT-APP.md** with correct ABI signatures and examples. (H-3)
5. **Fix README.md** code examples with correct function signatures. (H-4)

### Should-Fix Before Mainnet

6. **Enforce authorized supply can only increase**, not decrease. (H-5)
7. **Implement annual issuance tracking** to enforce the 20% rule. (H-6)
8. **Implement staggered governance seat terms** at transition per spec requirement. (H-7)
9. **Reconcile EIP draft** with current architecture — update struct definitions, remove bitfield, add partial redemption. (H-8)
10. **Add slippage protection** to ProtocolFeeLiquidator. (M-6)

### Should-Fix Pre-Launch

11. Correct thesis.md's claim that Pacts are "immutable". (M-1)
12. Reconcile gas estimates across documents. (M-2)
13. Add snapshot-based voting or use `ERC20Votes` for governance. (C-3 extension)
14. Clean up clause ID naming inconsistencies. (M-5, I-6, I-7)

---

## Conclusion

The Stake Protocol's smart contracts implement a coherent architecture (vesting on Claims, unconditional Stakes, vault-based transition with governance seats). However, the documentation ecosystem is severely fractured — the protocol specification, EIP draft, whitepaper, audit report, verification guide, and README all describe an **older, incompatible design** where vesting and revocation live on Stakes. Only `DESIGN.md` and the investment thesis align with the current code.

The most urgent security issue is the lack of voting snapshots for override proposals (C-3), which creates a governance manipulation vector. The most urgent documentation issue is the stale audit report (C-2), which creates a false sense of security while missing real issues in the current code.

The contracts themselves are well-structured and the architectural choice of "vesting on Claims, unconditional Stakes" is defensible and well-reasoned in `DESIGN.md`. The primary work needed is documentation reconciliation and implementation of spec-mandated safety features (snapshots, annual issuance limits, staggered terms).
