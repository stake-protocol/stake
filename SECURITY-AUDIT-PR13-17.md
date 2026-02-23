# Security Audit Report: PRs #13–#17

**Date**: 2026-02-23
**Scope**: Merge commits for PRs #13 through #17
**Auditor**: System Security Audit (automated)

---

## Summary

| PR | Commit | Title | Findings |
|----|--------|-------|----------|
| #13 | `396877d` | Update AUDIT.md with revised audit findings | 2 (Informational) |
| #14 | `306ab82` | Pause propagation, vault transfers, transition system | 8 findings (2 High, 3 Medium, 2 Low, 1 Informational) |
| #15 | `dc2caec` | Fix professional audit findings H-1/H-3/H-4/M-1/M-3/L-1/L-4/L-5 | 2 findings (1 Medium, 1 Low) |
| #16 | `820d6d5` | Make StakeCertificates sole registry admin | 0 findings (clean fix) |
| #17 | `93a7b60` | Align spec v0.4 with implemented contracts | 1 finding (Low) |

**Total**: 13 findings (2 High, 4 Medium, 3 Low, 4 Informational)

---

## PR #13 — Update AUDIT.md with revised audit findings

**Commit**: `396877d23db4332024a346e689c6b71df57bdbeb`
**Files changed**: `AUDIT.md` (1 file, documentation only)

### I-1: Audit date backdated

**Severity**: Informational
**File**: `AUDIT.md`, line 3
**Description**: The audit date was changed from `2026-02-06` to `2025-02-14`, which pre-dates the actual audit. This could be misleading to external reviewers who rely on the date to assess the audit's currency. The document should reflect when the revised audit was actually performed.

**Recommendation**: Use the actual date of the revised audit, not a backdated date.

### I-2: Severity reduction without corresponding code fixes in same PR

**Severity**: Informational
**File**: `AUDIT.md`
**Description**: The revised AUDIT.md significantly reduces the number and severity of findings (from 4 Critical + 8 High + 11 Medium to a smaller set) and removes multiple findings entirely (e.g., the original C-1 "No Emergency Pause", C-2 "Constructor deploys child contracts", H-2 "No issuer_id validation", H-4 "No batch operations"). While subsequent PRs (#14, #15) do fix several of these issues, this PR was merged before those fixes landed. The audit document should not downgrade findings until the corresponding code fixes are merged and verified.

**Recommendation**: Audit report revisions should be sequenced after the corresponding code fixes, or should clearly state which findings are "pending fix in PR #X".

---

## PR #14 — Pause propagation, vault transfers, transition system

**Commit**: `306ab82eebda9a1497f97e85b11fe0ceb14a7d62`
**Files changed**: 7 files (+1578, -238 lines)

This is the largest PR in the set. It introduces the Pausable mechanism, vault-based governance transition, StakeToken (ERC-20), StakeVault, ProtocolFeeLiquidator, and fixes the revocation logic (C-3/C-4 from original audit).

### H-1: Flash loan / double-voting governance attack in StakeVault override mechanism

**Severity**: High
**File**: `contracts/src/StakeVault.sol`, lines 463–476 (`voteOverride` function)
**Description**: The `voteOverride` function determines voting weight via `token.governanceBalance(msg.sender)`, which simply returns `balanceOf(msg.sender)` (for non-excluded addresses). There is no snapshot or checkpoint mechanism in `StakeToken`.

After the lockup period expires, token holders can freely transfer tokens. An attacker could:
1. Vote on an override proposal with weight W.
2. Transfer all tokens to a second address they control.
3. Vote again from the second address with the same tokens.

This effectively allows double (or N-times) voting by cycling tokens through multiple addresses. Additionally, after lockup, an attacker could use a flash loan (if the token is listed on a lending protocol) to temporarily acquire a large governance balance, vote, and return the tokens in the same transaction.

The `StakeToken` has no ERC20Votes/ERC20Snapshot functionality to prevent this.

**Recommendation**: Implement ERC20Votes (OpenZeppelin) with checkpointed balances. Use `getPastVotes(account, blockNumber)` at the proposal's snapshot block for voting weight, not live `balanceOf`.

### H-2: No slippage protection in ProtocolFeeLiquidator

**Severity**: High
**File**: `contracts/src/ProtocolFeeLiquidator.sol`, lines 149–160 (`liquidate` function)
**Description**: The `liquidate()` function calls `ILiquidationRouter(router).liquidate(token, tokensSold, treasury)` with no minimum output amount parameter. The `ILiquidationRouter` interface itself has no slippage parameter:

```solidity
function liquidate(address tokenIn, uint256 amountIn, address recipient) external returns (uint256 amountOut);
```

Since `liquidate()` is permissionless (anyone can call it), and the function is designed to be called by MEV bots/keepers, sandwich attacks are virtually guaranteed:
1. MEV bot sees `liquidate()` in the mempool.
2. Bot front-runs with a large buy, driving up the price.
3. `liquidate()` executes at the inflated price, receiving fewer output tokens.
4. Bot back-runs with a sell, pocketing the difference.

The protocol treasury receives less than fair value for every liquidation.

**Recommendation**: Add a `minAmountOut` parameter to both `ILiquidationRouter.liquidate()` and `ProtocolFeeLiquidator.liquidate()`. Consider using a TWAP oracle to calculate minimum acceptable output. At minimum, allow the caller to specify slippage tolerance.

### M-1: StakeVault has no pause mechanism

**Severity**: Medium
**File**: `contracts/src/StakeVault.sol` (entire contract)
**Description**: `StakeCertificates` propagates pause to child contracts (CLAIM, STAKE) via `pause()` and `unpause()`. However, `StakeVault` does not inherit `Pausable` and has no emergency stop mechanism. If a vulnerability is discovered in the vault's auction, token claiming, or override logic, there is no way to halt operations.

The vault holds custody of all post-transition certificates and controls token minting. It is a high-value target that should have circuit-breaker capability.

**Recommendation**: Add `Pausable` to `StakeVault` with `whenNotPaused` guards on `processTransitionBatch`, `claimTokens`, `bidForSeat`, `settleAuction`, `proposeOverride`, `voteOverride`, and `executeOverride`. The pauser should be the OPERATOR_ROLE or a dedicated PAUSER_ROLE.

### M-2: Unbounded loop in executeOverride may exceed block gas limit

**Severity**: Medium
**File**: `contracts/src/StakeVault.sol`, lines 495–520 (`executeOverride` function)
**Description**: `executeOverride` iterates over the entire `depositedStakeIds` array to find and reclaim all active governance seats:

```solidity
for (uint256 i; i < depositedStakeIds.length; i++) {
    uint256 certId = depositedStakeIds[i];
    GovernanceSeat storage seat = seats[certId];
    if (seat.active) {
        stakeContract.transferFrom(formerGovernor, address(this), certId);
        if (seat.bidAmount > 0) token.transfer(formerGovernor, seat.bidAmount);
        // ...
    }
}
```

Each iteration that processes an active seat performs an ERC-721 transfer and an ERC-20 transfer. If the protocol has hundreds or thousands of deposited stakes, this loop could exceed the block gas limit (~30M on mainnet), making override execution impossible.

**Recommendation**: Implement batched override execution, or track active governance seats in a separate bounded array/set rather than scanning all deposited stakes.

### M-3: StakeToken authorizedSupply can be increased without limit by governance

**Severity**: Medium
**File**: `contracts/src/StakeToken.sol`, lines 98–103 (`setAuthorizedSupply` function)
**Description**: The `setAuthorizedSupply` function allows the GOVERNANCE_ROLE to increase the authorized supply to any value:

```solidity
function setAuthorizedSupply(uint256 newSupply) external onlyRole(GOVERNANCE_ROLE) {
    if (newSupply < totalSupply()) revert InvalidSupply();
    authorizedSupply = newSupply;
}
```

If the governance key is compromised, an attacker can set an arbitrarily high authorized supply and then mint unlimited tokens via the vault's MINTER_ROLE (which is the vault). While governance compromise is a general risk, the lack of any maximum cap or time-lock on supply changes amplifies the impact.

**Recommendation**: Consider adding a maximum authorized supply set at deployment, or require a time-locked governance proposal for supply increases. At minimum, emit the old and new values (which is already done via `AuthorizedSupplyChanged`).

### L-1: bidForSeat minimum bid is zero for revoked stakes with zero units

**Severity**: Low
**File**: `contracts/src/StakeVault.sol`, lines 371–372
**Description**: The minimum bid for a governance seat is calculated as `(s.units * auctionMinBidBps) / BPS_BASE`. For a fully revoked stake (RevocationMode.ANY), `s.units` is 0, making the minimum bid 0. An attacker could win a governance seat for free on a revoked certificate. While a revoked cert with 0 units carries 0 governance weight, it still occupies the seat and could be used for griefing or confusion.

**Recommendation**: Prevent auctions on certificates with zero units, or set a minimum absolute bid amount.

### L-2: processTransitionBatch has no duplicate stakeId protection

**Severity**: Low
**File**: `contracts/src/StakeVault.sol`, lines 175–232
**Description**: `processTransitionBatch` does not check if a stakeId has already been processed. While submitting a duplicate stakeId would cause the `transferFrom` to fail (since the vault already owns it after the first processing), the operator could accidentally waste gas on large batches with duplicates. There is also no check that the `transitionProcessed` flag prevents re-processing — it's set on first call but subsequent calls are allowed (by design, for batching), so the operator must be careful.

**Recommendation**: Add a `processed` flag to `DepositedCert` or check `depositedStakes[stakeId].originalHolder != address(0)` before processing.

### I-3: Vault holds unrestricted custody over all soulbound tokens

**Severity**: Informational
**File**: `contracts/src/StakeCertificates.sol`, lines 196–203 (`_update` override in `SoulboundERC721`)
**Description**: The vault bypass in `_update` passes `address(0)` as the auth parameter to `super._update`, which skips all ERC-721 authorization checks (ownership, approval, operator). This means the vault can transfer any soulbound token from any address at any time without the holder's consent or approval.

This is by design for the transition and governance seat mechanics. However, it represents a significant trust assumption — the vault address, once set (via `setVault`, which can only be called once), has permanent, irrevocable, unchecked custody power over all tokens in both the CLAIM and STAKE contracts.

**Recommendation**: Document this trust assumption clearly. Consider adding an event when vault-initiated transfers occur, separate from standard ERC-721 Transfer events, to improve auditability.

---

## PR #15 — Fix professional audit findings

**Commit**: `dc2caecd0cd251350da8b552c8ed7d233c491cb8`
**Files changed**: 3 files (+397, -55 lines)

This PR fixes H-1 (partial redemption), H-3 (base URI control), H-4 (authority rotation), M-1 (void vs revocation), M-3 (batch issuance), L-1 (base URI events), L-4 (tryGetPact), and L-5 (production deploy script).

### M-4: transferAuthority does not propagate roles to child contracts (partially fixed by PR #16)

**Severity**: Medium (at time of PR #15; resolved by PR #16)
**File**: `contracts/src/StakeCertificates.sol`, lines 771–793 (`transferAuthority` function)
**Description**: In PR #15, `transferAuthority` transfers `DEFAULT_ADMIN_ROLE`, `AUTHORITY_ROLE`, and `PAUSER_ROLE` on the `StakeCertificates` contract. However, at the time of PR #15, the `StakePactRegistry` was constructed with `new StakePactRegistry(authority_, address(this))`, giving the original authority EOA `DEFAULT_ADMIN_ROLE` on the registry.

After calling `transferAuthority`, the old authority retains `DEFAULT_ADMIN_ROLE` on the registry and could:
1. Grant themselves `OPERATOR_ROLE` on the registry.
2. Create or amend pacts directly, bypassing `StakeCertificates` access controls.

**Note**: This was fixed in PR #16 by changing the registry constructor to `new StakePactRegistry(address(this), address(this))`, making `StakeCertificates` the sole admin. The fix is clean and correct.

**Recommendation**: Already fixed by PR #16. No further action needed, but the sequencing gap between PR #15 and #16 means any deployment between these two PRs would have the vulnerability.

### L-3: issueClaimBatch forces uniform unitType and redeemableAt across all recipients

**Severity**: Low
**File**: `contracts/src/StakeCertificates.sol`, lines 905–940 (`issueClaimBatch` function)
**Description**: The batch issuance function accepts arrays for `issuanceIds`, `recipients`, and `maxUnitsArr`, but uses a single `unitType` and `redeemableAt` for all claims in the batch. This limits the function to homogeneous issuances. Mixed-type batches (e.g., some SHARES, some BPS) require separate transactions.

**Recommendation**: Consider accepting `UnitType[]` and `uint64[]` arrays if heterogeneous batches are a use case. Alternatively, document this limitation clearly.

---

## PR #16 — Make StakeCertificates sole registry admin

**Commit**: `820d6d5e914d293fe94e8a33735f728f5db84e78`
**Files changed**: 2 files (+18, -1 lines)

This is a focused, clean fix. The registry constructor call is changed from `new StakePactRegistry(authority_, address(this))` to `new StakePactRegistry(address(this), address(this))`, ensuring no external EOA has direct admin access to the registry.

**No issues found.** The fix correctly addresses the privilege retention vulnerability from PR #15. The test verifies that the authority EOA cannot directly grant roles on the registry.

---

## PR #17 — Align spec v0.4 with implemented contracts

**Commit**: `93a7b6028e62c5c2b7cec48e7ef8da2beca25d14`
**Files changed**: 1 file (`spec/STAKE-PROTOCOL.md`, +248, -144 lines)

This PR updates the spec to v0.4, aligning it with the implemented contracts. It properly documents: onchain vs offchain pact fields, boolean status fields (replacing the bitfield), partial redemption, authority rotation, child contract admin model, vault bypass mechanics, and the override governance system.

### L-4: Spec states reclaimSeat auto-opens a new auction, but implementation does not

**Severity**: Low
**File**: `spec/STAKE-PROTOCOL.md`, §15.5 ("Seat Term End and Reclamation")
**Description**: The spec states (step 4 of reclamation): "Opens a new auction for the seat." However, the `reclaimSeat()` function in `StakeVault.sol` does not call `startSeatAuction()`. A separate permissionless call is required to start the next auction. This is a minor spec/implementation discrepancy that persists after PR #17.

**Recommendation**: Either update the spec to say "The seat becomes available for a new auction (initiated by any caller via `startSeatAuction`)" or update `reclaimSeat()` to automatically start the next auction.

---

## Cross-PR Observations

### Sequencing Risk Between PRs #15 and #16

PR #15 introduced `transferAuthority` while the registry still had the authority EOA as admin. PR #16 fixed this one commit later. Any deployment between these two PRs would have been vulnerable to privilege retention. For critical security fixes, consider atomic PRs that include both the feature and its hardening.

### Missing Tests for New Contracts

PR #14 introduces three new contracts (`StakeVault`, `StakeToken`, `ProtocolFeeLiquidator`) totaling ~895 lines of Solidity, but no dedicated test files for these contracts are included. All tests remain in `StakeCertificates.t.sol` and only cover the pre-transition lifecycle. The vault's governance, auction, override, token claiming, and liquidation logic have zero test coverage.

### No Reentrancy Guard on StakeToken

`StakeToken` does not use `ReentrancyGuard`. While standard ERC-20 transfers don't have reentrancy vectors (no callbacks), the lockup whitelist mechanism and the interaction with the vault's `nonReentrant` functions should be validated with integration tests.

---

## Findings Summary Table

| ID | PR | Severity | Title |
|----|-----|----------|-------|
| I-1 | #13 | Informational | Audit date backdated |
| I-2 | #13 | Informational | Severity reduction before code fixes |
| H-1 | #14 | High | Flash loan / double-voting governance attack |
| H-2 | #14 | High | No slippage protection in ProtocolFeeLiquidator |
| M-1 | #14 | Medium | StakeVault has no pause mechanism |
| M-2 | #14 | Medium | Unbounded loop in executeOverride |
| M-3 | #14 | Medium | Unlimited authorizedSupply increase |
| L-1 | #14 | Low | Zero minimum bid for revoked stakes |
| L-2 | #14 | Low | No duplicate stakeId protection in batch |
| I-3 | #14 | Informational | Vault holds unrestricted custody |
| M-4 | #15 | Medium | transferAuthority privilege retention (fixed by #16) |
| L-3 | #15 | Low | Batch issuance forces uniform params |
| L-4 | #17 | Low | Spec/impl gap: reclaimSeat auto-auction |
