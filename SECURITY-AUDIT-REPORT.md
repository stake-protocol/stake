# Stake Protocol — Comprehensive Security Audit Report

**Audit Date**: February 23, 2026
**Scope**: Full repository including all 23 merged PRs, 5 smart contracts, protocol spec, whitepaper, design decisions, EIP draft, thesis, and all supporting documentation.
**Methodology**: Each PR was checked out at its merge commit and its diff reviewed. The final state of all contracts and documentation was then audited line-by-line.

---

## Executive Summary

The Stake Protocol is a soulbound equity certificate system with an optional transition to ERC-20 tokens and governance. The codebase has undergone significant architectural evolution across 23 PRs, culminating in a design where vesting lives on Claims (contingent certificates) and Stakes are unconditional ownership records.

**Total Findings: 42**

| Severity | Count |
|----------|-------|
| Critical | 3 |
| High | 7 |
| Medium | 11 |
| Low | 12 |
| Informational | 9 |

The most severe issues are: (1) a governance seat holder can permanently brick the override mechanism by burning their certificate, (2) override voting is vulnerable to flash loan attacks due to lack of snapshots, and (3) the protocol specification is fundamentally out of sync with the implemented contracts.

---

## Critical Findings

### C-01: Governance Seat Holder Can Permanently DoS Override Mechanism via `burn()`

**Contract**: `SoulboundStake.sol` / `StakeVault.sol`
**Lines**: `SoulboundStake:699-705`, `StakeVault:452-467`

`SoulboundStake.burn()` allows any holder to destroy their certificate. A governance seat winner holds their certificate in their wallet. If they call `burn(stakeId)`, the certificate is destroyed. When `executeOverride()` later runs, it iterates `depositedStakeIds` and calls `stakeContract.transferFrom(formerGovernor, address(this), certId)` for each active seat. This call will revert on the burned token (ERC-721 `ownerOf` reverts for non-existent tokens), causing the entire override transaction to revert.

**Impact**: A single malicious governor can permanently disable the token holder override ("nuclear option") for ALL governance seats — not just their own. This is because `executeOverride` has no try/catch and iterates all seats in a single transaction. The override is the only mechanism token holders have to replace captured governance. Disabling it permanently eliminates the safety valve.

**Proof of Concept**:
1. Governor wins seat for `certId=5` via auction
2. Governor calls `stake.burn(5)` — certificate is destroyed
3. Any future `executeOverride()` call reverts when it tries to `transferFrom` on the burned token
4. All governance seats are now irremovable

`reclaimSeat()` for that specific seat will also permanently revert, meaning the governor's bid tokens are locked forever in the vault.

---

### C-02: Flash Loan Governance Attack on Override Voting

**Contract**: `StakeVault.sol`
**Lines**: `StakeVault:416-431`

`voteOverride()` reads voting weight from `token.governanceBalance(msg.sender)` at call time. There is no snapshot mechanism. An attacker can:

1. Flash-borrow a large quantity of tokens
2. Call `voteOverride(proposalId, true/false)` with the borrowed balance as weight
3. Return the tokens in the same transaction

The spec (§21.6) explicitly states: "Override votes SHOULD use a snapshot mechanism where voting power is determined at proposal creation, not at vote time." This is not implemented.

**Impact**: Any override vote can be decided by flash loans, completely undermining the governance safety mechanism.

---

### C-03: Spec Is Fundamentally Out of Sync with Implementation

**Files**: `spec/STAKE-PROTOCOL.md` vs all `.sol` contracts

The specification describes a system that does not match the deployed contracts. The code underwent a major architectural refactoring in PR #23 (moving vesting from Stakes to Claims, making Stakes unconditional), but the spec was never fully updated. Key mismatches:

| Spec Section | Spec Says | Code Does |
|---|---|---|
| §6.4 StakeState | 11 fields including vestStart, vestCliff, vestEnd, revokedAt, revocableUnvested, revokedUnits | 4 fields: issuedAt, unitType, units, reasonHash |
| §6.3 ClaimState | 8 fields, no vesting | 11 fields including vestStart, vestCliff, vestEnd, revokedAt |
| §9.2 | Stake revocation with vesting snapshot | No stake revocation; revocation is on Claims |
| §11.3 IStakeCertificate | `mintStake(to, pactId, units, unitType, vestStart, vestCliff, vestEnd, revocableUnvested)` | `mintStake(to, pactId, units, unitType)` — 4 params, no vesting |
| §11.4 IStakeCertificates | `redeemToStake(redemptionId, claimId, units, unitType, vestStart, vestCliff, vestEnd, reasonHash)` — 8 params | `redeemToStake(redemptionId, claimId, units, reasonHash)` — 4 params |
| §11.4 IStakeCertificates | `issueClaim(issuanceId, to, pactId, maxUnits, unitType, redeemableAt)` — 6 params | `issueClaim(issuanceId, to, pactId, maxUnits, unitType, redeemableAt, vestStart, vestCliff, vestEnd)` — 9 params |
| §11.4 IStakeCertificates | Has `revokeStake(stakeId, reasonHash)` | Has `revokeClaim(issuanceId, reasonHash)` instead |
| §11.1 IPactRegistry | `createPact` has 9 params including `defaultRevocableUnvested` | `createPact` has 8 params, no `defaultRevocableUnvested` |
| §11.5 IStakeVault | Has `releaseVestedTokens(stakeId)` | No such function exists (stakes are unconditional) |
| §12.2 | "Mint ERC-20 tokens = vestedUnits at transition" | Mints tokens = all units (stakes are fully owned) |
| §13.3 | "Unvested units at transition are NOT lost. Vault tracks vesting." | No vesting tracking in vault; all units are fully owned |
| §4.4 | "A Stake MAY include vesting metadata" | Stakes have no vesting; Claims have vesting |
| §6.2 | StakeState has `revoked` boolean field | StakeState has no `revoked` field |

This is not a cosmetic documentation issue. Anyone implementing against the spec will build an incompatible system. Anyone auditing against the spec will reach incorrect conclusions about the security model.

---

## High Severity Findings

### H-01: `transferAuthority(currentAuthority)` Self-Transfer Bricks Contract

**Contract**: `StakeCertificates.sol`
**Lines**: `792-808`

If the authority calls `transferAuthority(authority)` (passing their own address), the `_grantRole` calls are no-ops (roles already held), then `_revokeRole` removes all three roles (DEFAULT_ADMIN_ROLE, AUTHORITY_ROLE, PAUSER_ROLE). The authority permanently loses all access.

```solidity
function transferAuthority(address newAuthority) external onlyRole(AUTHORITY_ROLE) whenNotTransitioned {
    if (newAuthority == address(0)) revert InvalidAuthority();
    address oldAuthority = authority;
    authority = newAuthority;
    _grantRole(DEFAULT_ADMIN_ROLE, newAuthority);  // no-op if same address
    _grantRole(AUTHORITY_ROLE, newAuthority);       // no-op if same address
    _grantRole(PAUSER_ROLE, newAuthority);          // no-op if same address
    _revokeRole(DEFAULT_ADMIN_ROLE, oldAuthority);  // removes the role
    _revokeRole(AUTHORITY_ROLE, oldAuthority);       // removes the role
    _revokeRole(PAUSER_ROLE, oldAuthority);          // removes the role
}
```

**Impact**: Permanently bricks the entire protocol. No pacts, claims, stakes, or transitions can ever be created again. Missing check: `if (newAuthority == oldAuthority) revert InvalidAuthority();`

---

### H-02: StakeBoard Single-Member Execution After Response Window

**Contract**: `StakeBoard.sol`
**Lines**: `210-250`

After the response deadline, the adjusted quorum formula is `ceil(quorum * responded / totalMembers)`. On a 5-member board with quorum=3, if only 1 member responds (the proposer, who auto-approves), the adjusted quorum becomes `ceil(3 * 1 / 5) = ceil(0.6) = 1`. Since the proposer auto-approved, the single member can execute any proposal.

**Impact**: Any board member can unilaterally execute arbitrary actions on the StakeCertificates contract by simply waiting for the response window to expire. This bypasses the entire multisig governance model.

---

### H-03: StakeBoard Zero Response Window Allows Instant Execution

**Contract**: `StakeBoard.sol`
**Lines**: `321-325`

`setResponseWindow(uint64 newWindow)` accepts 0. With `responseWindow = 0`, a proposer can create a proposal and execute it in the same block (or even same transaction via a contract), since `deadline = createdAt + 0 = createdAt` and `block.timestamp > deadline` is immediately true post-creation.

**Impact**: Combined with H-02, a single board member can change the response window to 0 and then execute any number of arbitrary proposals without any other member's consent.

---

### H-04: `executeOverride()` Unbounded Loop Gas DoS

**Contract**: `StakeVault.sol`
**Lines**: `452-467`

`executeOverride()` iterates the entire `depositedStakeIds` array. This array grows with every stake deposited during transition and is never pruned. For a large cap table (e.g., thousands of stakes), this loop can exceed the block gas limit.

```solidity
for (uint256 i; i < depositedStakeIds.length; i++) {
    // ... process each seat
}
```

**Impact**: For companies with many stakeholders, the override mechanism becomes permanently unusable because the transaction will always exceed the block gas limit.

---

### H-05: Override Voting Allows Double-Voting via Token Transfer

**Contract**: `StakeVault.sol`
**Lines**: `416-431`

Even without flash loans, a token holder can vote, then transfer tokens to another address they control, and vote again from that address. The `hasVoted` check only prevents the same address from voting twice, not the same tokens from being counted twice.

**Impact**: Any holder can multiply their voting power by the number of addresses they control, making override vote outcomes untrustworthy.

---

### H-06: Stale AUDIT.md Misrepresents Security Status

**File**: `AUDIT.md`

The audit report references an outdated architecture (stakes with vesting and revocation). Every finding it reports has been addressed by the architectural refactoring in PR #23, yet the document still presents them as current issues. The spec-to-implementation gap table is entirely wrong.

**Impact**: Anyone relying on the audit report to assess the current security posture will have a fundamentally incorrect understanding of the system. More dangerously, they may believe previously identified issues are still outstanding when they've been architecturally eliminated, or may miss new issues introduced by the refactoring.

---

### H-07: Spec's `IStakeVault` Interface Doesn't Match Implementation

**Files**: `spec/STAKE-PROTOCOL.md` §11.5, `StakeVault.sol`

The spec defines:
```solidity
function processTransitionBatch(uint256[] calldata stakeIds, address liquidationRouter) external;
function releaseVestedTokens(uint256 stakeId) external;
```

The implementation:
```solidity
function processTransitionBatch(uint256[] calldata stakeIds) external;  // no liquidationRouter param
function deployLiquidator(address liquidationRouter) external;          // separate function
// releaseVestedTokens does not exist
```

**Impact**: Any integration built against the spec's interface will fail at deployment.

---

## Medium Severity Findings

### M-01: No Slippage Protection in ProtocolFeeLiquidator

**Contract**: `ProtocolFeeLiquidator.sol`
**Lines**: `146-158`

The `liquidate()` function calls `ILiquidationRouter.liquidate(token, tokensSold, treasury)` with no minimum output amount parameter. The `ILiquidationRouter` interface itself has no `minAmountOut`.

**Impact**: Every liquidation is vulnerable to sandwich attacks. MEV bots can manipulate the pool price before the liquidation, extract value from the swap, and restore the price afterward.

---

### M-02: Unredeemed Claims Become Worthless After Transition

**Contract**: `StakeCertificates.sol`
**Lines**: `1017-1027`

`redeemToStake()` has both `onlyRole(AUTHORITY_ROLE)` and `whenNotTransitioned` modifiers. After `initiateTransition()`, the authority loses AUTHORITY_ROLE and the `transitioned` flag is set. Claims that were issued but not yet redeemed cannot be redeemed.

**Impact**: Holders with unredeemed claims (e.g., unvested options not yet at cliff) lose their entire position at transition. There is no mechanism to redeem claims post-transition.

---

### M-03: `setAuthorizedSupply` Allows Supply Decrease

**Contract**: `StakeToken.sol`
**Lines**: `96-101`

The spec (§14.2) says authorized supply "MAY only be increased by a token holder supermajority vote." The code allows any value >= `totalSupply()`, including decreasing the authorized supply. This could be used to block future legitimate minting.

---

### M-04: No Annual Issuance Tracking for 20% Rule

**Contract**: `StakeToken.sol`

The spec (§14.3) mandates that annual issuance beyond 20% of outstanding supply requires a token holder vote. The `StakeToken` contract has no tracking of annual issuance amounts, annual period boundaries, or any enforcement of this 20% threshold. `governanceMint()` can mint up to the full authorized supply in a single call.

**Impact**: The anti-dilution safeguard described in §16.3 does not exist in the code.

---

### M-05: No Staggered Governance Seat Terms at Transition

**Contract**: `StakeVault.sol`

The spec (§15.2) states: "At transition, seats MUST be assigned staggered initial term expiry dates." The vault has no mechanism for staggering terms. All seats go through the same auction process with the same term length.

**Impact**: All governance seats could turn over simultaneously, creating a governance continuity gap.

---

### M-06: `vestStart=0` with Non-Zero `vestEnd` Causes Near-Instant Vesting

**Contract**: `StakeCertificates.sol` (SoulboundClaim)
**Lines**: `604-619`

If `issueClaim` is called with `vestStart=0` and `vestEnd` set to a future timestamp, the vesting calculation computes elapsed time from Unix epoch (timestamp 0). Since `block.timestamp` is ~1.7 billion, virtually all units would vest immediately.

```solidity
uint256 elapsed = timestamp - c.vestStart;  // ~1.7 billion if vestStart=0
uint256 duration = c.vestEnd - c.vestStart;  // vestEnd (e.g., 1.7B + 4 years)
return (c.maxUnits * elapsed) / duration;    // ~98% vested immediately
```

**Impact**: Claims intended to have multi-year vesting schedules would be immediately claimable if the authority accidentally sets `vestStart=0` but `vestEnd` to a non-zero value. The validation only checks `vestStart <= vestCliff && vestCliff <= vestEnd` when `vestEnd != 0`, but doesn't validate that `vestStart` is reasonable.

---

### M-07: Vault Operator Retains Permanent DEFAULT_ADMIN_ROLE

**Contract**: `StakeVault.sol`
**Lines**: `171-172`

The vault operator receives `DEFAULT_ADMIN_ROLE` and `OPERATOR_ROLE` in the constructor. There is no mechanism to renounce these roles. The operator can:
- Grant OPERATOR_ROLE to any address
- Grant DEFAULT_ADMIN_ROLE to any address
- Maintain permanent privileged access

**Impact**: The "app can die" guarantee (§21.1) does not hold for the vault. If the operator key is compromised, the attacker has permanent, irrevocable admin access.

---

### M-08: Governance Mint Bypasses Lockup

**Contract**: `StakeToken.sol`
**Lines**: `109-112`

`governanceMint(address to, uint256 amount)` can mint tokens to any address without setting a lockup. The `processTransitionBatch` function sets lockups for original holders, but governance can mint new tokens to addresses with no lockup, allowing immediate selling.

---

### M-09: Auction Minimum Bid Rounds to Zero for Small Stakes

**Contract**: `StakeVault.sol`
**Lines**: `323-325`

```solidity
uint256 minBid = (s.units * auctionMinBidBps) / BPS_BASE;
```

For stakes with fewer than `BPS_BASE / auctionMinBidBps` units (i.e., fewer than 10 units with default 10% minimum), the minimum bid rounds to 0. Combined with the check `if (amount < minBid)` (not `<=`), a bid of 0 tokens would satisfy the minimum.

---

### M-10: `reclaimSeat` Does Not Auto-Open Auction

**Contract**: `StakeVault.sol`
**Lines**: `375-393`

The spec (§15.5) states that `reclaimSeat` should open a new auction: "Opens a new auction for the seat." The implementation does not start a new auction — it only returns the certificate to the vault. Someone must separately call `startSeatAuction()`.

---

### M-11: Incomplete Role Revocation at Transition

**Contract**: `StakeCertificates.sol`
**Lines**: `844-848`

`initiateTransition()` only revokes roles from `authority` (the current authority variable). If additional addresses were granted roles directly via OpenZeppelin's `grantRole()` (which is possible since `authority` holds `DEFAULT_ADMIN_ROLE` pre-transition), those addresses retain their roles after transition.

---

## Low Severity Findings

### L-01: `burn()` Works When Paused

**Contract**: `StakeCertificates.sol` (SoulboundStake)
**Lines**: `699-705`

`SoulboundStake.burn()` has no `whenNotPaused` modifier. Holders can burn their stakes even when the protocol is paused. While this is documented as intentional ("it's their property"), it means pause cannot prevent destructive operations.

---

### L-02: Smart Wallet Check Bypassable During Contract Construction

**Contract**: `StakeCertificates.sol`
**Lines**: `921`

`to.code.length == 0` returns true during contract construction (before the constructor finishes). An EOA could deploy a contract that calls `issueClaim` in the constructor with itself as recipient, bypassing the smart wallet check. The recipient would end up being a contract, so this is a minor bypass.

---

### L-03: `issueClaimBatch` Forces Uniform Parameters

**Contract**: `StakeCertificates.sol`
**Lines**: `940-977`

`issueClaimBatch` takes a single `unitType`, `redeemableAt`, `vestStart`, `vestCliff`, `vestEnd` for all recipients. If different recipients need different parameters, multiple batch calls or individual calls are needed.

---

### L-04: No Duplicate StakeId Protection in `processTransitionBatch`

**Contract**: `StakeVault.sol`
**Lines**: `199-231`

While there is an `AlreadyDeposited` check, a malicious operator could include the same stakeId twice in the same batch. The first iteration would process it; the second would revert the entire batch. The check prevents double-processing across batches but could DoS a single batch.

Actually, this is handled: `if (depositedStakes[stakeId].originalHolder != address(0)) revert AlreadyDeposited();` — the second encounter in the same batch would revert because the first already set `originalHolder`. This is correct but the revert is batch-wide, not per-item.

---

### L-05: CI Slither Analysis Uses `continue-on-error: true`

**File**: `.github/workflows/ci.yml`

The Slither static analysis step has `continue-on-error: true`, meaning security findings from Slither never block CI. PRs with critical Slither findings can merge without review.

---

### L-06: Gas Snapshots Auto-Regenerate on Failure

**File**: `.github/workflows/ci.yml`

```yaml
run: forge snapshot --check --tolerance 5 || forge snapshot
```

If gas usage increases beyond 5% tolerance, instead of failing, the CI regenerates the snapshot. Gas regressions are silently accepted.

---

### L-07: CI Uses Nightly Foundry Toolchain

**File**: `.github/workflows/ci.yml`

`version: nightly` means the build toolchain changes daily. This can cause non-deterministic builds and silent compilation behavior changes.

---

### L-08: No Event for Response Window Change on StakeBoard

**Contract**: `StakeBoard.sol`

While `ResponseWindowUpdated` event is defined and emitted, there's no minimum value validation on `setResponseWindow`. Setting it to 0 (see H-03) has severe implications but emits only a benign event.

---

### L-09: Revert Data Suppression in StakeBoard

**Contract**: `StakeBoard.sol`
**Lines**: `246-247`

```solidity
(bool success,) = target.call(p.data);
if (!success) revert ExecutionFailed();
```

The revert data from the target call is discarded. If the target call fails, the only error is `ExecutionFailed()` with no indication of why the underlying call reverted.

---

### L-10: `onERC721Received` on StakeVault but Uses `transferFrom` Not `safeTransferFrom`

**Contract**: `StakeVault.sol`
**Lines**: `495-497`

The vault implements `onERC721Received` for ERC-721 compatibility, but the actual transfers use `transferFrom` (not `safeTransferFrom`). The callback will never be called through the protocol's own operations.

---

### L-11: Verification Guide Has Wrong ABI Signatures

**File**: `docs/VERIFY-WITHOUT-APP.md`

The guide references old function signatures that no longer match the current contract ABIs (e.g., missing `unitType` parameter on `issueClaim`, presence of `revokeStake` which no longer exists on the coordinator).

---

### L-12: README Code Examples Use Outdated Signatures

**File**: `README.md`

Code examples reference old function signatures and architectural patterns that don't match the current contracts.

---

## Informational Findings

### I-01: EIP Draft Uses Bitfield Status Flags

**File**: `eip/eip-draft.md`

The EIP draft describes certificate status using a bitfield (`ACTIVE | VOIDED | REDEEMED | REVOKED = 0x01 | 0x02 | 0x04 | 0x08`). Both the spec (§6.2) and code use separate boolean fields. The three documents are inconsistent.

---

### I-02: AUDIT.md Date Is Backdated

**File**: `AUDIT.md`

The audit report shows dates from 2025 despite being created in February 2026.

---

### I-03: Thesis Contains Unverifiable Claims

**File**: `thesis.md`

References to "Vitalik's February 2026 posts" and specific market size figures should be verifiable. These are editorial claims, not security issues.

---

### I-04: No Test Coverage for StakeVault, StakeBoard, or ProtocolFeeLiquidator

**Files**: `contracts/test/`

Only `StakeCertificates.t.sol` and `StakeToken.t.sol` exist. There are no tests for the post-transition contracts (StakeVault, StakeBoard, ProtocolFeeLiquidator). All vault, auction, governance seat, override, and liquidation logic is untested.

---

### I-05: No Fuzz Tests

**Files**: `contracts/test/`

The test suite uses only fixed inputs. No fuzz testing, no invariant testing. Critical numerical logic (vesting calculations, quorum math, fee calculations) should be fuzz tested.

---

### I-06: DESIGN.md Describes 31 Design Decisions Spanning Obsolete and Current Architecture

**File**: `DESIGN.md`

The design decisions document covers the full evolution of the protocol including decisions that were later reversed by the architectural refactoring. While useful as a historical record, it doesn't clearly distinguish current architecture from superseded decisions.

---

### I-07: `.env.example` Shows Private Key Format

**File**: `contracts/.env.example`

`DEPLOYER_PRIVATE_KEY=0x...` is visible. While `.gitignore` properly excludes `.env` files, showing the format in the example could lead to copy-paste errors.

---

### I-08: `defaultRevocableUnvested` Referenced in Spec But Removed from Code

**Files**: `spec/STAKE-PROTOCOL.md` §5.2.1, `StakeCertificates.sol`

The Pact struct in the spec includes `default_revocable_unvested`, but the actual `Pact` struct in the code does not have this field (it was removed when revocation moved to Claims). The `IPactRegistry.createPact` in the spec still has this parameter.

---

### I-09: Whitepaper Describes Outdated Architecture

**File**: `WHITEPAPER.md`

The whitepaper describes the original architecture where stakes have vesting and revocation. It should be updated to reflect the current architecture where claims handle vesting and stakes are unconditional.

---

## Summary of Spec vs Implementation Mismatches

The protocol underwent a fundamental architectural change in PR #23 that moved vesting and revocation from Stakes to Claims. This change was correctly implemented in the contracts and test suite, but the following documents were NOT updated:

| Document | Status |
|---|---|
| `spec/STAKE-PROTOCOL.md` | **Partially updated** — lifecycle overview is correct, but §6.3/§6.4 field tables, §9.2 revocation rules, §11.x interfaces, §12.2 transition process, and §13.3 token distribution all describe the old architecture |
| `WHITEPAPER.md` | **Not updated** — describes old architecture throughout |
| `eip/eip-draft.md` | **Not updated** — uses bitfield status, old interfaces |
| `AUDIT.md` | **Not updated** — all findings reference old architecture |
| `docs/VERIFY-WITHOUT-APP.md` | **Not updated** — wrong function signatures |
| `README.md` | **Not updated** — wrong code examples |
| `DESIGN.md` | **Partially updated** — covers architectural evolution but doesn't clearly mark superseded decisions |
| `thesis.md` | **Current** — describes the protocol at a high level correctly |

---

## Recommendations

### Immediate (Before Any Deployment)

1. **Fix C-01**: Add a mechanism to prevent `burn()` on certificates held by governance seat winners, or add try/catch in `executeOverride()` to handle burned certificates gracefully.
2. **Fix C-02**: Implement snapshot-based voting for override proposals. Record each voter's balance at proposal creation time and use that for weight calculation.
3. **Fix H-01**: Add `if (newAuthority == authority) revert InvalidAuthority();` to `transferAuthority()`.
4. **Fix H-02/H-03**: Add a minimum response window validation in `setResponseWindow()` and consider a minimum adjusted quorum floor (e.g., at least 2 approvals regardless of response rate).
5. **Fix M-01**: Add slippage protection (`minAmountOut`) to the `ILiquidationRouter` interface and `ProtocolFeeLiquidator.liquidate()`.
6. **Fix M-06**: Validate `vestStart` is not 0 when `vestEnd` is non-zero, or validate `vestStart >= block.timestamp - REASONABLE_LOOKBACK`.

### Before Production

7. **Fix C-03**: Fully update the spec, whitepaper, EIP draft, audit report, verification guide, and README to match the current architecture.
8. **Fix M-02**: Add a post-transition redemption mechanism or explicitly warn issuers that all claims must be redeemed before transition.
9. **Fix M-04**: Implement the 20% annual issuance tracking described in the spec.
10. **Fix M-07**: Add a mechanism for the vault operator to renounce their admin role after transition processing is complete.
11. Add comprehensive test suites for `StakeVault`, `StakeBoard`, and `ProtocolFeeLiquidator`.
12. Add fuzz tests for vesting calculations, quorum math, and fee calculations.
13. Make Slither CI non-soft-fail.

### Long-Term

14. Consider implementing ERC-20 voting snapshots (e.g., ERC-20Votes from OpenZeppelin) for all governance mechanisms.
15. Consider adding a circuit breaker or rate limiter to `governanceMint` to enforce the 20% annual rule onchain.
16. Consider pagination for `executeOverride()` to handle large cap tables within block gas limits.

---

*Report generated by comprehensive audit of all 23 merged PRs and final codebase state.*
