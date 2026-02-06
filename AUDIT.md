# Stake Protocol — Full Audit Report

**Date**: 2026-02-06
**Scope**: All contracts, documentation, specs, deployment scripts, and tests
**Target**: Ethereum Mainnet L1
**Commit**: HEAD on main branch

---

## Executive Summary

Stake Protocol is a soulbound equity certificate system implementing a Pact -> Claim -> Stake lifecycle on ERC-721. The codebase is compact (~759 lines of Solidity), well-structured, and all 42 tests pass. However, the protocol has **several critical and high-severity issues that must be resolved before Ethereum mainnet deployment**, along with numerous spec-to-implementation gaps, missing test coverage, and operational concerns specific to L1 gas economics.

### Severity Counts

| Severity | Count |
|----------|-------|
| Critical | 4 |
| High | 8 |
| Medium | 11 |
| Low | 9 |
| Informational | 7 |

---

## CRITICAL Issues

### C-1: No Emergency Pause Mechanism

**Location**: All contracts
**Impact**: If a vulnerability is discovered post-deployment, there is no way to halt operations. On L1 mainnet, this is unacceptable for a contract holding equity records.

The spec itself acknowledges this at `spec/STAKE-PROTOCOL.md:396`:
> Production deployments should consider: Emergency pause mechanisms

Yet the implementation has none. There is no `Pausable` inheritance, no circuit breaker, and no way to freeze issuance, redemption, or revocation during an incident.

**Recommendation**: Implement OpenZeppelin's `Pausable` on `StakeCertificates` with `whenNotPaused` guards on all state-changing functions. Add a `PAUSER_ROLE` separate from `AUTHORITY_ROLE`.

---

### C-2: Constructor Deploys Child Contracts — Deterministic Address Risk on L1

**Location**: `StakeCertificates.sol:599-601`

```solidity
REGISTRY = new StakePactRegistry(authority, address(this));
CLAIM = new SoulboundClaim(address(this), ISSUER_ID, REGISTRY);
STAKE = new SoulboundStake(address(this), ISSUER_ID, REGISTRY);
```

Deploying three child contracts inside the constructor via `new` means:
1. **Deployment gas is enormous** — the initcode of `StakeCertificates` is 30,020 bytes (carrying bytecode of all 4 contracts). This will cost ~4-6M gas on mainnet at current prices.
2. **No CREATE2 determinism** — addresses of child contracts are determined by deployer nonce, not by salt. This makes cross-chain reproducibility impossible and complicates Etherscan verification.
3. **Re-deployment requires re-deploying everything** — a bug in any child contract requires redeploying the entire system.

**Recommendation**: Deploy child contracts separately via `CREATE2` or pass them as constructor arguments. This reduces gas, enables deterministic addresses, and allows independent upgrades.

---

### C-3: Revocation Sets a Boolean Flag But Does Not Reduce Units

**Location**: `SoulboundStake.revokeStake()` at `StakeCertificates.sol:530-556`

When `revocationMode == UNVESTED_ONLY`, the contract checks that unvested units > 0 and then sets `s.revoked = true`. However, **the contract never actually reduces `s.units`**. The revoked stake still reports the same `units` value. The `vestedUnits()` function still returns vesting calculations against the original total.

This means:
- After revocation, `getStake()` still shows the original unit count
- `vestedUnits()` still calculates against the full amount
- There is no way to determine what was actually revoked vs. retained
- Any downstream system reading `units` will see incorrect ownership

The spec says (`spec/STAKE-PROTOCOL.md:242`):
> revocation MUST only affect the unvested portion

But the implementation does not track or record what portion was revoked. The boolean `revoked` flag is binary — it cannot represent partial revocation.

**Recommendation**: On revocation under `UNVESTED_ONLY`, calculate vested units at revocation time, reduce `s.units` to the vested amount, and store the revoked amount. Alternatively, add a `revokedUnits` field to `StakeState` and snapshot the vested amount at revocation time.

---

### C-4: Revoked Stakes Continue Vesting

**Location**: `SoulboundStake.vestedUnits()` at `StakeCertificates.sol:463-478`

The `vestedUnits()` function does not check whether a stake has been revoked. A revoked stake continues to report increasing vested units as time passes. Combined with C-3, this means:

1. Authority revokes an employee's stake on day 100 (500 of 1000 units vested)
2. On day 200, `vestedUnits()` reports 750 vested (continuing to vest after revocation)
3. The `revoked` boolean is true, but the vesting math ignores it entirely

Any off-chain system, indexer, or UI relying on `vestedUnits()` will show incorrect data for revoked stakes.

**Recommendation**: `vestedUnits()` must check `s.revoked` and, if true, return the vested amount at the time of revocation (which needs to be stored — see C-3).

---

## HIGH Issues

### H-1: No UnitType Stored on Claims or Stakes

**Location**: `ClaimState` struct (line 68), `StakeState` struct (line 77)

The spec defines a `unit_type` field (SHARES, BPS, WEI, CUSTOM) at `spec/STAKE-PROTOCOL.md:142-150` and the `UnitType` enum exists in the contract (line 45-50), but **neither `ClaimState` nor `StakeState` actually stores it**. The `issueClaim()` and `mintStake()` functions don't accept a `unitType` parameter.

This means there is no way to know whether 1000 units means 1000 shares, 10% ownership (1000 BPS), or 1000 wei. This is a critical data gap for a production equity system.

**Recommendation**: Add `UnitType unitType` to both structs and both issuance functions.

---

### H-2: No `issuer_id` Validation or Multi-Issuer Support

**Location**: `StakeCertificates.sol:594`

```solidity
ISSUER_ID = keccak256(abi.encode(block.chainid, authority));
```

The `ISSUER_ID` is derived from `chainid + authority` and is immutable. This means:
1. If the protocol is deployed on a testnet first (chainid 11155111) and then mainnet (chainid 1), the `ISSUER_ID` changes, breaking any cross-reference
2. There is no way to represent the same legal issuer across different contract deployments
3. The `issuerId` in Pact creation is hardcoded to `ISSUER_ID` — issuers cannot set their own namespace

For L1 mainnet deployment, the ISSUER_ID should be a stable, externally-defined identifier.

**Recommendation**: Accept `issuerId` as a constructor parameter or allow the authority to set it explicitly.

---

### H-3: `amendPact()` Inherits All Fields From Old Pact Including `revocationMode`

**Location**: `StakePactRegistry.amendPact()` at `StakeCertificates.sol:271-306`

When amending a pact, the new pact inherits `revocationMode`, `mutablePact`, and `defaultRevocableUnvested` from the old pact with no ability to change them. An amendment can only update `contentHash`, `rightsRoot`, `uri`, and `pactVersion`.

This means:
- An issuer who creates a pact with `RevocationMode.ANY` can never tighten it to `UNVESTED_ONLY`
- An issuer who creates a pact with `mutablePact = true` can never freeze it
- The `defaultRevocableUnvested` flag is permanently locked

The spec mentions amendment_mode and amendment_scope as configurable per-pact (`spec/STAKE-PROTOCOL.md:91-92`), but the implementation hardcodes inheritance of all governance fields.

**Recommendation**: Allow `amendPact()` to optionally update `revocationMode` (only to stricter modes), and allow `mutablePact` to be set to `false` (one-way lock).

---

### H-4: No Batch Operations — Gas Prohibitive on L1

**Location**: `StakeCertificates.sol` — all issuance functions

On Ethereum L1, each `issueClaim()` costs ~213K gas and each `redeemToStake()` costs ~222K gas. For a company issuing equity to 50 employees:
- 50 claims: ~10.65M gas
- 50 redemptions: ~11.1M gas
- Total: ~21.75M gas (~$2,000-5,000 at typical L1 gas prices)

There are no batch functions (`issueClaimBatch`, `redeemToStakeBatch`). Each operation is a separate transaction.

**Recommendation**: Add batch variants of `issueClaim()` and `redeemToStake()` that operate on arrays. Consider `multicall` pattern for composability.

---

### H-5: No Event Emitted for UnitType, ConversionHash, or VestingHash

**Location**: Events throughout `StakeCertificates.sol`

The spec defines rich certificate metadata including `conversionHash`, `vestingHash`, `revocationHash` (`spec/STAKE-PROTOCOL.md:138`). None of these hashes are emitted in events or stored on-chain. The `ClaimIssued` event only emits `(claimId, pactId, to, maxUnits, redeemableAt)`. The `StakeMinted` event only emits `(stakeId, pactId, to, units)`.

This means off-chain indexers cannot reconstruct the full certificate provenance from events alone, contradicting the spec's goal of evidentiary clarity.

**Recommendation**: Add `conversionHash` to `ClaimIssued` and `vestingHash` to `StakeMinted` events.

---

### H-6: Partial Redemption Marks Claim as Fully Redeemed

**Location**: `StakeCertificates.redeemToStake()` at `StakeCertificates.sol:690-733`

The code allows partial redemption (`units < maxUnits`), as shown in `test_PartialRedemption()`. However, after partial redemption, `CLAIM.markRedeemed()` is called, which sets `c.redeemed = true`. This makes the claim permanently redeemed.

This means: If a Claim for 1000 units is redeemed for 500 units, the remaining 500 units are lost — the claim is marked redeemed and cannot be used again.

The spec (section 4.3) implies a claim converts to a stake, but doesn't address partial redemption semantics. If partial redemption is intended, the claim should track remaining units.

**Recommendation**: Either (a) remove partial redemption support and require `units == maxUnits`, or (b) track `redeemedUnits` on the claim and only mark fully redeemed when all units are consumed.

---

### H-7: `_update()` Allows Burns But Protocol Has No Burn Function

**Location**: `SoulboundERC721._update()` at `StakeCertificates.sol:143-150`

```solidity
if (from != address(0) && to != address(0)) revert Soulbound();
```

This blocks transfers but allows burns (to == address(0)). The ERC-721 `_burn()` function is inherited and callable by any contract with the appropriate internal access. While no public burn function exists, this is a latent risk — if any future extension calls `_burn()`, certificates can be permanently destroyed with no revocation/void record.

**Recommendation**: Also block burns in `_update()` unless explicitly intended. If burns are needed, route them through `voidClaim`/`revokeStake` to maintain audit trail.

---

### H-8: No `tokenURI` Metadata Standard for On-Chain Resolution

**Location**: `SoulboundERC721.tokenURI()` at `StakeCertificates.sol:132-137`

The `tokenURI` function returns `baseURI + tokenId` or empty string if no base URI is set. The spec says (`spec/STAKE-PROTOCOL.md:138`):
> tokenURI JSON SHOULD include issuer_id, pact_id, certificate type, and relevant hashes

But there is no on-chain metadata generation. If the base URI is not set (or the off-chain server goes down), certificates have no metadata. For a soulbound equity system, the token metadata should be generated on-chain (like Lido's stETH or Uniswap V3 positions) to ensure survivability.

**Recommendation**: Implement on-chain SVG/JSON metadata generation via `tokenURI()`, or at minimum store the Pact URI reference in the token metadata. The `docs/VERIFY-WITHOUT-APP.md` guide promotes on-chain verifiability, but `tokenURI` returns nothing by default.

---

## MEDIUM Issues

### M-1: Spec Defines 4 Revocation Modes, Contract Implements 3

**Location**: `spec/STAKE-PROTOCOL.md:93` vs `StakeCertificates.sol:39-43`

Spec defines:
- 0 = none
- 1 = unvested_only
- 2 = per_stake_flags
- 3 = external_rules_hash

Contract implements:
- 0 = NONE
- 1 = UNVESTED_ONLY
- 2 = ANY

`per_stake_flags` and `external_rules_hash` are missing. `ANY` is not in the spec. This divergence means the implementation cannot represent the full spec.

---

### M-2: Spec Defines Amendment Modes Not Implemented

**Location**: `spec/STAKE-PROTOCOL.md:91-92`

The spec defines:
- `amendment_mode`: 0=none, 1=issuer_only, 2=multisig_threshold, 3=external_rules_hash
- `amendment_scope`: 0=future_only, 1=retroactive_allowed_if_flagged

None of these are implemented. The contract uses a simple `mutablePact` boolean. There is no multisig threshold support, no external rules, and no retroactive amendment handling.

---

### M-3: Spec Defines Signing Modes Not Implemented

**Location**: `spec/STAKE-PROTOCOL.md:96`

The spec defines `signing_mode`: 0=issuer_only, 1=countersign_required_offchain, 2=countersign_required_onchain.

The contract has no signing mode concept. There is no countersignature flow. All operations are issuer-only.

---

### M-4: Spec Defines Dispute Fields Not Implemented

**Location**: `spec/STAKE-PROTOCOL.md:94-95`

The spec defines `dispute_law` and `dispute_venue` as Pact fields. These are not stored in the `Pact` struct or emitted in events. For a legal equity instrument, these are important metadata fields.

---

### M-5: Spec Defines `custom_terms_hash` Not Implemented

**Location**: `spec/STAKE-PROTOCOL.md:98`

The `custom_terms_hash` field from the spec is not in the `Pact` struct.

---

### M-6: Spec Defines Status Flags Bitfield, Contract Uses Individual Booleans

**Location**: `spec/STAKE-PROTOCOL.md:151-162` vs structs

The spec defines a `uint32 status_flags` bitfield with bits for VOIDED, REVOKED, REDEEMED, DISPUTED. The contract uses individual `bool voided`, `bool redeemed`, `bool revoked` fields with no DISPUTED state. This wastes storage (3 storage slots vs 1) and diverges from the spec.

---

### M-7: No `DISPUTED` State

**Location**: `spec/STAKE-PROTOCOL.md:159`

The spec defines bit 3 as DISPUTED status. The contract has no dispute mechanism whatsoever. For a legal equity instrument on mainnet, dispute flagging is important for freezing certificates during legal proceedings.

---

### M-8: `getPact()` Reverts Instead of Returning Empty — Breaks Composability

**Location**: `StakePactRegistry.getPact()` at `StakeCertificates.sol:215-219`

`getPact()` reverts with `PactNotFound` if the pact doesn't exist. This breaks composability — other contracts cannot safely check if a pact exists without try/catch. The `pactExists()` function exists but requires a separate call.

**Recommendation**: Consider returning a boolean success flag, or document that callers must use `pactExists()` first.

---

### M-9: `ISSUER_ID` Computation Uses `block.chainid` — Fork Risk

**Location**: `StakeCertificates.sol:594`

If Ethereum forks (as it has historically), `block.chainid` changes and all `ISSUER_ID` references become invalid on the fork chain. The `ISSUER_ID` is `immutable`, so it captures deployment-time chainid. Any post-fork pact lookups using a different chainid will fail.

---

### M-10: `redeemToStake()` Does Not Validate `vestStart` Against Claim's `issuedAt`

**Location**: `StakeCertificates.redeemToStake()` at `StakeCertificates.sol:690-733`

The authority can set `vestStart` to any value, including timestamps in the far past. This could be used to issue stakes that appear fully vested from inception, bypassing the intent of vesting schedules. There is no validation that `vestStart >= claim.issuedAt` or `vestStart >= block.timestamp`.

---

### M-11: No Reentrancy Protection

**Location**: All state-changing functions

While current code flow doesn't have obvious reentrancy vectors (no ETH transfers, no external calls to untrusted contracts), the cross-contract call pattern (StakeCertificates -> SoulboundClaim/SoulboundStake -> StakePactRegistry) means a malicious registry could theoretically re-enter. Consider adding `ReentrancyGuard` for defense-in-depth on L1 mainnet.

---

## LOW Issues

### L-1: No Events on `setBaseURI()`

**Location**: `SoulboundERC721.setBaseURI()` at `StakeCertificates.sol:124-126`

Base URI changes are not tracked via events, making it impossible for indexers to detect metadata changes.

---

### L-2: `nextId` Starts at 1 But Is Not Documented

**Location**: `SoulboundClaim.nextId` (line 321), `SoulboundStake.nextId` (line 437)

Token IDs start at 1, which is good (avoids 0-confusion), but this is not documented and there's no getter for the total supply.

---

### L-3: No `totalSupply()` or Certificate Counting

**Location**: All contracts

There is no way to query total claims issued, total stakes minted, or iterate over certificates. On L1 where event scanning is expensive, adding ERC-721 Enumerable or simple counters would help.

---

### L-4: Deployment Script Defaults to Insecure Configuration

**Location**: `Deploy.s.sol:64-65`

```solidity
bytes32 contentHash = vm.envOr("PACT_CONTENT_HASH", keccak256("default pact"));
bytes32 rightsRoot = vm.envOr("PACT_RIGHTS_ROOT", keccak256("default rights"));
```

`DeployAndCreatePact` defaults to `keccak256("default pact")` for content hash. A production deployment with these defaults would reference meaningless hashes. The script should require these values rather than defaulting.

---

### L-5: No Input Validation on URI Strings

**Location**: `createPact()`, `amendPact()`

Empty URIs and arbitrary strings are accepted. For production, at minimum validate non-empty URIs or that they start with expected prefixes (`ipfs://`, `ar://`, `https://`).

---

### L-6: `markRedeemed()` Reuses `ClaimNotRedeemable` Error for Already-Redeemed

**Location**: `SoulboundClaim.markRedeemed()` at `StakeCertificates.sol:405-415`

If a claim is already redeemed, the error `ClaimNotRedeemable` is thrown. This is the same error as when a claim is voided, making debugging ambiguous. Should use `AlreadyRedeemed` error.

---

### L-7: `voidClaim()` on StakeCertificates Uses `issuanceId`, but Underlying `SoulboundClaim.voidClaim()` Uses `claimId`

**Location**: `StakeCertificates.voidClaim()` at line 681

The coordinator wraps `issuanceId -> claimId` lookup. But there's no way to void a claim by `claimId` directly through the coordinator, and no way to void a claim via `issuanceId` on the underlying `SoulboundClaim` contract. This asymmetry could cause operational confusion.

---

### L-8: Gas Snapshot Tolerance at 5% May Mask Regressions

**Location**: `.github/workflows/ci.yml:39`

```yaml
forge snapshot --check --tolerance 5 || forge snapshot
```

The `||` fallback means gas snapshot checks never actually fail CI. If a snapshot check fails, it just regenerates the snapshot. This provides no protection against gas regressions.

---

### L-9: Slither CI Uses `continue-on-error: true`

**Location**: `.github/workflows/ci.yml:62`

```yaml
continue-on-error: true
```

Slither findings never block CI. For a mainnet-bound contract, static analysis should be a required check.

---

## INFORMATIONAL Issues

### I-1: EIP Interface IDs Listed as TBD

**Location**: `spec/STAKE-PROTOCOL.md:296-300`

`IPactRegistry`, `IClaimCertificate`, and `IStakeCertificate` interface IDs are "TBD". These need to be computed and registered before mainnet launch. The contract also doesn't advertise these interfaces via `supportsInterface()`.

---

### I-2: EIP Draft Has Placeholder Author and Discussion URL

**Location**: `eip/eip-draft.md:6-7`

```
author: TBD (@username)
discussions-to: https://ethereum-magicians.org/t/erc-soulbound-equity-certificates/TBD
```

---

### I-3: `via_ir = true` in Foundry Config

**Location**: `contracts/foundry.toml:8`

IR compilation is enabled. While this produces more optimized bytecode, it's known to occasionally produce different behavior than legacy compilation. Ensure the final deployment bytecode is verified with the exact same compiler settings.

---

### I-4: No Formal Verification Setup

For an equity certificate system on L1, formal verification of core invariants (soulbound enforcement, vesting math, revocation correctness) is strongly recommended. Tools like Certora, Halmos, or Kontrol should be considered.

---

### I-5: Test Coverage Gaps

The test suite covers 42 scenarios but is missing:

1. **Fuzz tests**: No property-based testing for vesting math, unit boundaries, or overflow scenarios
2. **Invariant tests**: No invariant testing (e.g., "total vested never exceeds units", "revoked stakes don't vest further")
3. **Multi-actor scenarios**: No tests with multiple issuers, multiple pacts, or complex redemption chains
4. **Access control matrix**: No comprehensive test of every role against every function
5. **Edge cases**: No tests for `vestStart == vestCliff == vestEnd` with non-zero time, no tests for `uint64` timestamp overflow (year 2106+), no tests for very large unit values near `uint256` max
6. **Amended pact behavior**: No tests verifying behavior of certificates issued under an old pact after amendment
7. **`RevocationMode.ANY`**: No tests for ANY mode revocation behavior
8. **Claim voiding under `RevocationMode.NONE`**: The `voidClaim()` checks revocation mode, but claims should arguably be voidable even when revocation is disabled (voiding != revoking)

---

### I-6: SECURITY.md Has No Contact Email

**Location**: `SECURITY.md:10`

> Email security concerns to the maintainers (contact information in repository)

No actual email address is provided anywhere in the repository.

---

### I-7: README References "Coming Soon" EIP Discussion

**Location**: `README.md:156`

> [EIP Discussion](https://ethereum-magicians.org/) (Coming Soon)

---

## Spec-to-Implementation Gap Summary

| Spec Feature | Spec Section | Implemented? |
|---|---|---|
| `unit_type` on certificates | 6.1 | No |
| `status_flags` bitfield | 6.2 | No (uses booleans) |
| `conversionHash` on Claims | 6.3 | No |
| `vestingHash` on Stakes | 6.4 | No |
| `revocationHash` on Stakes | 6.4 | No |
| `DISPUTED` status flag | 6.2 | No |
| `amendment_mode` enum | 5.2 | No (boolean only) |
| `amendment_scope` enum | 5.2 | No |
| `signing_mode` enum | 5.2 | No |
| `dispute_law` field | 5.2 | No |
| `dispute_venue` field | 5.2 | No |
| `custom_terms_hash` field | 5.2 | No |
| `per_stake_flags` revocation | 5.2 | No |
| `external_rules_hash` revocation | 5.2 | No |
| Claim `schema` field | 6.3 | No |
| Stake `schema` field | 6.4 | No |
| `IPactRegistry` ERC-165 ID | 11.4 | No |
| `IClaimCertificate` ERC-165 ID | 11.4 | No |
| `IStakeCertificate` ERC-165 ID | 11.4 | No |
| Batch/mass distribution | 10 | No |
| Self-claim mode | 10.2 | No |
| Emergency pause | 14.4 | No |
| Proxy upgradeability | 14.4 | No |

---

## L1 Mainnet-Specific Concerns

### Gas Economics

| Operation | Gas Cost | Est. USD at 30 gwei, ETH=$3000 |
|---|---|---|
| Deploy StakeCertificates | ~4-6M | $360-540 |
| createPact | ~205K | $18.45 |
| issueClaim | ~214K | $19.26 |
| redeemToStake | ~222K | $19.98 |
| revokeStake | ~variable | ~$10-15 |

For a 50-person cap table: ~$2,500-4,000 in gas for initial setup.

**No batch operations exist.** Each claim and stake is a separate transaction. On L2, this is acceptable; on L1, it's operationally painful and expensive.

### Block Size Considerations

The `StakeCertificates` initcode is 30,020 bytes. This is within the 49,152 byte contract size limit but leaves only 19,132 bytes of margin. The runtime size (6,303 bytes) is fine.

### MEV Considerations

Front-running risk is low since all operations are authority-gated. However, a compromised authority key could issue fraudulent certificates that get confirmed before the team notices. Timelock + multisig is strongly recommended.

---

## Recommendations for Mainnet Launch

### Must-Fix (Block Launch)

1. **Fix revocation logic** — revoked stakes must stop vesting and record the vested amount at revocation time (C-3, C-4)
2. **Add emergency pause** (C-1)
3. **Add `unitType` to certificate structs** (H-1)
4. **Fix partial redemption semantics** — either disallow or track remaining units (H-6)

### Should-Fix (High Priority)

5. Add batch issuance and redemption functions (H-4)
6. Deploy child contracts separately, not in constructor (C-2)
7. Add `vestingHash`/`conversionHash` to events (H-5)
8. Allow `amendPact()` to tighten governance params (H-3)
9. Make `ISSUER_ID` a constructor parameter (H-2)
10. Add on-chain tokenURI metadata generation (H-8)

### Should-Fix (Pre-Launch)

11. Add fuzz tests and invariant tests (I-5)
12. Add reentrancy guards (M-11)
13. Add dispute flagging mechanism (M-7)
14. Fix CI to actually enforce Slither and gas snapshots (L-8, L-9)
15. Add formal verification for vesting math and soulbound enforcement (I-4)
16. Resolve spec-to-implementation gaps or update spec to match (all M-1 through M-6)

### Nice-to-Have

17. Add `totalSupply()` counters (L-3)
18. Add events for base URI changes (L-1)
19. Add proper error types for disambiguation (L-6)
20. Validate URI formats (L-5)

---

## Conclusion

The Stake Protocol has a sound design philosophy and a clean, readable codebase. The spec is thoughtful and covers the right concepts. However, the implementation is a **reference-quality prototype, not mainnet-ready code**. The critical issues around revocation logic (C-3, C-4) are correctness bugs that will cause real equity accounting errors. The lack of emergency pause (C-1) is a non-starter for L1 mainnet. The gas economics (H-4) and deployment architecture (C-2) need rethinking for L1 specifically.

Before mainnet deployment, I recommend:
1. Fix all Critical and High issues
2. Add comprehensive fuzz/invariant testing
3. Get an independent professional audit (Trail of Bits, OpenZeppelin, Spearbit, etc.)
4. Run a testnet deployment and simulate the full lifecycle end-to-end
5. Consider formal verification for the vesting math
