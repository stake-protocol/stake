# Stake Protocol — Audit Report

**Date**: 2025-02-14  
**Scope**: Solidity contracts (`contracts/src`), tests (`contracts/test`), deployment scripts (`contracts/script`), specs/docs (`spec`, `docs`, `README.md`, `WHITEPAPER.md`)  
**Commit**: Local working tree (pre-commit)

---

## Executive Summary

Stake Protocol implements a compact Pact → Claim → Stake lifecycle with soulbound ERC-721 certificates. The core architecture is straightforward and role-gated, but **several correctness and robustness gaps remain**. The most serious issue is **revocation logic that does not snapshot vested units and does not stop vesting**, causing revoked stakes to keep accruing vested units and misreport ownership. Additional high-severity findings include **partial redemption semantics that permanently discard remaining claim units**, **missing unit-type storage (spec divergence)**, **inability to set base URI/metadata due to role wiring**, and **authority/issuer identity immutability that blocks key rotation**.

The codebase should be treated as **prototype-quality** until these issues are addressed, spec/implementation gaps are reconciled, and test coverage is expanded with fuzz and invariant suites.

### Severity Summary

| Severity | Count |
|---|---:|
| Critical | 1 |
| High | 4 |
| Medium | 4 |
| Low | 5 |
| Informational | 4 |

---

## CRITICAL

### C-1: Revocation does not snapshot vested units and does not stop vesting

**Location**: `SoulboundStake.revokeStake`, `SoulboundStake.vestedUnits` in `contracts/src/StakeCertificates.sol`

When a stake is revoked, the implementation only toggles a boolean (`revoked`) and **does not**:
1. Snapshot the vested amount at revocation time.
2. Reduce `units` to the vested amount.
3. Prevent further vesting after revocation.

As a result, a revoked stake continues to report higher vested units over time, and the total units remain unchanged. This violates the spec requirement that revocation must only affect the unvested portion and leads to material misreporting of ownership.

**Recommendation**: On revocation, compute vested units, snapshot that value (e.g., `vestedAtRevocation`), reduce `units` to the vested amount (or track `revokedUnits`), and ensure `vestedUnits()` returns the snapshot for revoked stakes.

---

## HIGH

### H-1: Partial redemption permanently discards remaining claim units

**Location**: `StakeCertificates.redeemToStake` and tests in `contracts/test/StakeCertificates.t.sol`

`redeemToStake` permits `units < maxUnits`, then calls `CLAIM.markRedeemed`, which marks the claim fully redeemed. Any remaining units are lost, and the claim can never be redeemed again. The tests explicitly exercise partial redemption, but the implementation has no mechanism to track remaining units.

**Recommendation**: Either **disallow partial redemption** (`require(units == maxUnits)`) or add a `redeemedUnits` field and only mark fully redeemed once `redeemedUnits == maxUnits`.

---

### H-2: `unit_type` is defined in the spec but not stored on-chain

**Location**: `UnitType` enum exists, but `ClaimState`/`StakeState` omit it in `contracts/src/StakeCertificates.sol`

The spec requires a `unit_type` for every certificate (SHARES/BPS/WEI/CUSTOM), but the contracts never record it. This makes the `units` value ambiguous and breaks interoperability guarantees.

**Recommendation**: Add `UnitType unitType` to both `ClaimState` and `StakeState`, and require it in issuance/minting flows.

---

### H-3: Base URI cannot be set due to role wiring

**Location**: `SoulboundERC721.setBaseURI`, constructors for `SoulboundClaim`/`SoulboundStake`

`setBaseURI` is restricted to `ISSUER_ROLE`. The issuer for `SoulboundClaim`/`SoulboundStake` is the `StakeCertificates` contract itself, and there is **no forwarding function** on `StakeCertificates` to call `setBaseURI` or to grant roles. This makes base URI effectively immutable and keeps `tokenURI()` empty forever.

**Recommendation**: Add authority-controlled forwarding functions (or assign the authority as an issuer role) so base URIs can be set/updated.

---

### H-4: Authority and issuer identity cannot be rotated

**Location**: `StakeCertificates` constructor and `createPact`

`AUTHORITY` and `ISSUER_ID` are immutable and derived from the deployment-time authority address. If the authority key must be rotated, the immutable `AUTHORITY` and `ISSUER_ID` values remain tied to the old key, and newly created Pacts will still record the old authority address. This undermines operational security for long-lived deployments.

**Recommendation**: Allow authority rotation (e.g., `setAuthority`) and decouple `ISSUER_ID` from `block.chainid`+authority so it can be set explicitly.

---

## MEDIUM

### M-1: Claims cannot be voided when revocation is disabled

**Location**: `SoulboundClaim.voidClaim`

`voidClaim` checks the Pact’s `revocationMode` and reverts when it is `NONE`. The spec differentiates *void* (cancellation) from *revoke* (unvested clawback), so disabling revocation should not necessarily forbid voiding.

**Recommendation**: Clarify the intended policy and, if voiding should remain possible, allow it even when revocation is disabled.

---

### M-2: Vesting start can be backdated arbitrarily

**Location**: `StakeCertificates.redeemToStake`, `SoulboundStake.mintStake`

The only vesting validation is ordering (`vestStart <= vestCliff <= vestEnd`). There is no validation that `vestStart` is >= claim issuance time or >= current time. This enables the authority to mint stakes that appear fully vested immediately, potentially contradicting intended vesting policies.

**Recommendation**: Require `vestStart >= claim.issuedAt` (or >= `block.timestamp`) unless explicitly allowed by the Pact.

---

### M-3: No batch issuance/redemption paths

**Location**: `StakeCertificates` interface

All operations are single-item transactions. For large cap tables, gas costs and operational burden become significant, especially on L1.

**Recommendation**: Add `issueClaimBatch` and `redeemToStakeBatch` functions (or a multicall) for production deployment.

---

### M-4: Spec defines richer revocation/amendment modes than implemented

**Location**: `spec/STAKE-PROTOCOL.md` vs. `StakeCertificates.sol`

The spec includes `per_stake_flags`, `external_rules_hash`, and amendment/scope modes. The implementation only supports `NONE`, `UNVESTED_ONLY`, and `ANY` with a single `mutablePact` flag.

**Recommendation**: Either implement the missing modes or update the spec to match the implemented subset.

---

## LOW

### L-1: No event emitted when base URI changes

**Location**: `SoulboundERC721.setBaseURI`

Indexers cannot detect metadata changes since no event is emitted.

**Recommendation**: Emit an event such as `BaseURIUpdated(string newBaseURI)`.

---

### L-2: `tokenURI()` returns empty string when base URI is unset

**Location**: `SoulboundERC721.tokenURI`

If the base URI is empty (and currently it is immutable; see H-3), `tokenURI()` returns `""`, reducing certificate discoverability. For long-term onchain artifacts, an onchain JSON metadata fallback is preferable.

**Recommendation**: Provide onchain JSON/SVG metadata or at least include the Pact URI and hashes.

---

### L-3: Soulbound logic still permits burns if a burn function is added later

**Location**: `SoulboundERC721._update`

Transfers are blocked but burns (`to == address(0)`) are allowed. There is no public burn function today, but the invariant is fragile if future functions add burning.

**Recommendation**: Consider explicitly blocking burns or routing them through void/revoke flows to preserve auditability.

---

### L-4: `StakePactRegistry.getPact()` always reverts on missing pacts

**Location**: `StakePactRegistry.getPact`

Composability is reduced because callers must wrap in try/catch or do an extra `pactExists` call.

**Recommendation**: Add a `tryGetPact` that returns a `(bool exists, Pact memory)` tuple.

---

### L-5: Deployment script defaults to placeholder pact hashes

**Location**: `contracts/script/Deploy.s.sol`

`DeployAndCreatePact` uses `keccak256("default pact")` and `keccak256("default rights")` as fallbacks, which risks deploying with meaningless pact metadata.

**Recommendation**: Require explicit environment variables for pact content and rights roots in production deployments.

---

## INFORMATIONAL

### I-1: Spec includes transition/governance system not implemented

**Location**: `spec/STAKE-PROTOCOL.md`

The spec defines a Transition to tokenized governance with vaults, seat auctions, and issuer power freeze. None of this appears in the contracts. This is acceptable if the implementation is an early subset, but the spec should clearly state this scope.

---

### I-2: Certificate metadata in spec is not implemented

**Location**: `spec/STAKE-PROTOCOL.md`

The spec expects `schema`, `conversionHash`, `vestingHash`, `revocationHash`, and `status_flags`. These fields are not stored or emitted in the contract events.

---

### I-3: No formal verification or invariant testing

**Location**: `contracts/test`

Tests are unit-style and do not include fuzzing or invariants (e.g., “vested units never exceed units”, “revoked stakes do not vest”).

---

### I-4: Authority-bound issuer ID may be inconsistent across networks

**Location**: `StakeCertificates` constructor

`ISSUER_ID` is derived from `block.chainid` and authority. Deploying on multiple networks yields different issuer IDs for the same legal entity.

---

## Spec-to-Implementation Gap Summary

| Spec Feature | Spec Section | Implemented? |
|---|---|---|
| `unit_type` on certificates | 6.1 | No |
| `status_flags` bitfield | 6.2 | No |
| `conversionHash` on Claims | 6.3 | No |
| `vestingHash` on Stakes | 6.4 | No |
| `revocationHash` on Stakes | 6.4 | No |
| `DISPUTED` status flag | 6.2 | No |
| `amendment_mode` enum | 5.2 | No |
| `amendment_scope` enum | 5.2 | No |
| `signing_mode` enum | 5.2 | No |
| `dispute_law` / `dispute_venue` | 5.2 | No |
| Transition + Vault + Governance | 4.5, 12 | No |

---

## Recommendations (Prioritized)

### Must-Fix (Block Launch)
1. **Fix revocation logic** to snapshot vested units and prevent further vesting after revocation. (C-1)
2. **Resolve partial redemption** by forbidding partials or tracking `redeemedUnits`. (H-1)
3. **Store `unit_type` on all certificates**. (H-2)

### Should-Fix (High Priority)
4. Enable authority-controlled **metadata/baseURI updates**. (H-3)
5. Implement **authority rotation** or document immutability with operational controls. (H-4)
6. Add **batch issuance/redemption** for operational scalability. (M-3)

### Should-Fix (Pre-Launch)
7. Align the **spec** with the actual implementation or implement missing modes. (M-4, I-1, I-2)
8. Add **fuzz/invariant testing** for vesting, revocation, and idempotence properties. (I-3)
9. Revisit claim void policy vs. revocation policy for clarity. (M-1)
10. Add stronger **vesting validation** to prevent accidental backdating. (M-2)

---

## Conclusion

Stake Protocol’s contract suite is compact and readable, but several correctness and operational risks remain. The **revocation mechanics are the most urgent fix** because they directly impact ownership accounting. After addressing the critical and high-severity findings, the protocol should expand its tests, reconcile the spec with the implementation, and introduce operational safeguards (metadata control, authority rotation, batch operations) before any mainnet deployment.
