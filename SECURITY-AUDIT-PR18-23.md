# Security Audit Report: PRs #18–#23

**Date:** 2026-02-23
**Scope:** Merge commits for PRs #18 through #23 in the Stake Protocol repository
**Methodology:** Manual code review of each PR's diff against its parent commit

---

## PR #18 — Fix final audit: duplicate deposit guard, fee stranding, error cleanup

**Commit:** `cb3d2b29758d5095270b5c4bd9eb3301e1da7f34`
**Files changed:** `StakeCertificates.sol`, `StakeVault.sol`, `StakeCertificates.t.sol`

### Findings

#### 18-1. `auctionDuration` now set via constructor parameter without validation

| Field    | Value |
|----------|-------|
| Severity | Low |
| File     | `contracts/src/StakeVault.sol` |
| Location | Constructor parameter `auctionDuration_` |

**Description:** Previously `auctionDuration` was hardcoded to `7 days`. This PR makes it a constructor parameter (`auctionDuration_`). There is no minimum duration validation — a value of `0` would create auctions that end immediately in the same block they start (`end = start + 0`), allowing the first bidder to win instantly. While this is a constructor-only parameter (set once by the deployer), a misconfiguration could undermine the auction governance mechanism.

**Recommendation:** Add `require(auctionDuration_ >= 1 days)` or similar minimum check in the constructor.

#### 18-2. Pact existence check now relies on implicit revert

| Field    | Value |
|----------|-------|
| Severity | Informational |
| File     | `contracts/src/StakeCertificates.sol` |
| Location | `SoulboundClaim.issueClaim()` and `SoulboundStake.mintStake()` |

**Description:** The pact existence check changed from `Pact memory p = REGISTRY.getPact(pactId); if (p.pactId == bytes32(0)) revert PactNotFound();` to just `REGISTRY.getPact(pactId);`, relying on `getPact()` to revert internally if the pact doesn't exist. This is safe as long as `getPact()` does revert for non-existent pacts. The implicit behavior is documented in the comment "getPact reverts if not found."

#### 18-3. Positive: Duplicate deposit guard added

| Field    | Value |
|----------|-------|
| Severity | Informational (Positive) |
| File     | `contracts/src/StakeVault.sol` |
| Location | `processTransitionBatch()` |

**Description:** The addition of `if (depositedStakes[stakeId].originalHolder != address(0)) revert AlreadyDeposited();` correctly prevents the same stake from being processed twice across batches. Without this guard, a stake could be deposited multiple times, minting duplicate tokens. This is a well-implemented fix.

#### 18-4. Positive: Fee stranding prevention

| Field    | Value |
|----------|-------|
| Severity | Informational (Positive) |
| File     | `contracts/src/StakeVault.sol` |
| Location | `processTransitionBatch()` |

**Description:** The simplification to always accumulate protocol fees in the vault (rather than conditionally deploying or transferring to a liquidator) correctly prevents the scenario where tokens could be stranded in a liquidator whose `totalTokens` was already initialized from an earlier batch. `deployLiquidator()` is now a separate call made after all batches complete.

---

## PR #19 — Revoke all authority powers at transition; fix auction error names

**Commit:** `55bbe59683b696ddc0566921fddc6aacee8867e4`
**Files changed:** `StakeCertificates.sol`, `StakeVault.sol`, `StakeCertificates.t.sol`

### Findings

#### 19-1. Role revocation at transition only targets the `authority` variable

| Field    | Value |
|----------|-------|
| Severity | Medium |
| File     | `contracts/src/StakeCertificates.sol` |
| Location | `initiateTransition()`, lines revoking `PAUSER_ROLE`, `AUTHORITY_ROLE`, `DEFAULT_ADMIN_ROLE` |

**Description:** The `initiateTransition()` function revokes `PAUSER_ROLE`, `AUTHORITY_ROLE`, and `DEFAULT_ADMIN_ROLE` from the current `authority` address. However, OpenZeppelin's `AccessControl` exposes a public `grantRole()` function that the `DEFAULT_ADMIN_ROLE` holder can call to grant any role to any address. If the authority had used `grantRole()` directly (bypassing `transferAuthority()`) to grant roles to additional addresses before transition, those additional role holders would NOT be revoked at transition.

The `whenNotTransitioned` modifier on `pause()`, `unpause()`, `setClaimBaseURI()`, `setStakeBaseURI()`, and `transferAuthority()` provides defense-in-depth for those functions. However, other `AUTHORITY_ROLE`-gated functions (e.g., `createPact`, `issueClaim`, `voidClaim`, `revokeStake`, `redeemToStake`) only use `onlyRole(AUTHORITY_ROLE)` without `whenNotTransitioned`, so a stray role holder could still call them post-transition.

**Recommendation:** Either (1) add `whenNotTransitioned` to all `AUTHORITY_ROLE`-gated functions, or (2) enumerate all role holders and revoke (requires tracking), or (3) document that `grantRole()` must never be called directly.

#### 19-2. Positive: Child contract unpausing at transition

| Field    | Value |
|----------|-------|
| Severity | Informational (Positive) |
| File     | `contracts/src/StakeCertificates.sol` |
| Location | `initiateTransition()` |

**Description:** Automatically unpausing child contracts at transition (`if (CLAIM.paused()) CLAIM.unpause(); if (STAKE.paused()) STAKE.unpause();`) ensures the vault can always operate on certificates post-transition. Combined with `whenNotTransitioned` on `pause()`, this creates a strong guarantee that vault operations are unstoppable post-transition.

---

## PR #20 — Add board governance via multisig guidance to spec and whitepaper

**Commit:** `4e86fa354a23656fee3e2957d1ad38dea84993ca`
**Files changed:** `WHITEPAPER.md`, `spec/STAKE-PROTOCOL.md`

### Findings

#### 20-1. No security issues found

| Field    | Value |
|----------|-------|
| Severity | Informational |

**Description:** This PR adds documentation about using multisig wallets (e.g., Gnosis Safe) for board governance. The documentation correctly notes that:

- The protocol does NOT enforce that Pact-granted board seats match multisig signers (intentional decoupling).
- At transition, all authority roles are permanently revoked regardless of whether the authority is an EOA or multisig.
- Legal enforcement is the recourse for discrepancies.

The guidance is sound and consistent with the implementation in PRs #18/#19.

---

## PR #21 — Fix releaseVestedTokens underflow, add deployment binding checks

**Commit:** `d256acc5c13d766a90c9f88dd2686faaa4c9f1cb`
**Files changed:** `StakeToken.sol`, `StakeVault.sol`, `contracts/.gas-snapshot`

### Findings

#### 21-1. `protocolFeeAddress` zero-check uses wrong error name

| Field    | Value |
|----------|-------|
| Severity | Informational |
| File     | `contracts/src/StakeToken.sol` |
| Location | Constructor, `if (protocolFeeAddress_ == address(0)) revert InvalidSupply();` |

**Description:** The zero-address check for `protocolFeeAddress_` reuses the `InvalidSupply` error. A dedicated error like `InvalidAddress` would improve debuggability and make revert reasons unambiguous.

#### 21-2. Positive: Critical underflow fix in `releaseVestedTokens`

| Field    | Value |
|----------|-------|
| Severity | Informational (Positive — fixes a Critical bug) |
| File     | `contracts/src/StakeVault.sol` |
| Location | `releaseVestedTokens()`, floor clamp: `if (totalVestedNow < cert.vestedUnitsAtTransition) totalVestedNow = cert.vestedUnitsAtTransition;` |

**Description:** For revoked `UNVESTED_ONLY` stakes, `totalUnits` was set equal to `vestedUnitsAtTransition` (the stake's units were reduced to only the vested portion). However, the linear vesting interpolation `(totalUnits * elapsed) / duration` could produce a value *less than* `vestedUnitsAtTransition` when `elapsed < duration`, causing an arithmetic underflow in `newlyVested = totalVestedNow - cert.vestedUnitsAtTransition - cert.tokensClaimed`. The floor clamp correctly prevents this underflow. This was a real arithmetic bug that could cause token claims to revert permanently.

#### 21-3. Positive: Deployment binding checks

| Field    | Value |
|----------|-------|
| Severity | Informational (Positive) |
| File     | `contracts/src/StakeVault.sol` |
| Location | `processTransitionBatch()` |

**Description:** Adding `if (address(stakeContract.vault()) != address(this)) revert VaultNotBound();` and `if (!token.hasRole(token.MINTER_ROLE(), address(this))) revert VaultNotBound();` prevents deployment misconfigurations from silently bricking the transition or losing assets. These are excellent defensive checks.

---

## PR #22 — Claude/stake protocol thesis

**Commit:** `1064f8d5b43be26bfd91b1baec9172be885c3ce3`
**Files changed:** `thesis.md` (new file)

### Findings

#### 22-1. No security issues found

| Field    | Value |
|----------|-------|
| Severity | Informational |

**Description:** This PR adds a marketing/investment thesis document (`thesis.md`). The document contains no code, no secrets, no private keys, and no sensitive configuration. The claims about market data include sourced references. No security concerns.

---

## PR #23 — Claude/add thesis page

**Commit:** `071388109646a5f7810ef0d9fcf103f5e16d22fa`
**Files changed:** `DESIGN.md` (new), `StakeBoard.sol` (new), `StakeCertificates.sol`, `StakeToken.sol`, `StakeVault.sol`, `Deploy.s.sol`, `StakeCertificates.t.sol`, `StakeToken.t.sol` (new)

This is the largest PR in the set and contains significant architectural changes: vesting moves from Stakes to Claims, Stakes become irrevocable unconditional ownership, a new `StakeBoard` governance contract is introduced, and `governanceMint()` is added to `StakeToken`.

### Findings

#### 23-1. StakeBoard: Single member can execute proposals when others are unresponsive

| Field    | Value |
|----------|-------|
| Severity | High |
| File     | `contracts/src/StakeBoard.sol` |
| Location | `execute()`, adjusted quorum calculation |

**Description:** After the response deadline, non-responsive members are excluded from quorum calculation. The formula `adjustedQuorum = ceil(quorum * responded / totalMembers)` can reduce the effective quorum to 1.

Example with a 3-of-5 board: if only 1 member responds and approves, `adjustedQuorum = ceil(3 * 1 / 5) = ceil(0.6) = 1`. Since 1 approval >= 1 adjusted quorum, the proposal executes. A single board member (20% of the board) can unilaterally execute any board action — including issuing new equity, voiding claims, or initiating transition — simply by waiting for the response window to expire.

An adversarial member could submit a proposal during a period when communication is disrupted (holiday, infrastructure outage, timezone misalignment) and execute it unilaterally after the window.

**Recommendation:** Add a minimum absolute quorum floor (e.g., `adjustedQuorum = max(adjustedQuorum, min(2, totalMembers))`) to ensure at least 2 approvals are always required for multi-member boards. Alternatively, require that `responded >= quorum` as a prerequisite for post-deadline execution.

#### 23-2. StakeBoard: No deadline enforcement on `approve()` and `reject()`

| Field    | Value |
|----------|-------|
| Severity | Medium |
| File     | `contracts/src/StakeBoard.sol` |
| Location | `approve()` and `reject()` functions |

**Description:** Neither `approve()` nor `reject()` check whether `block.timestamp <= p.deadline`. Members can respond after the deadline, which changes `responseCount` and `approvalCount` and thus affects the adjusted quorum calculation in `execute()`. A late response could change a proposal's outcome after the deadline has passed.

Scenario: A 3-of-5 board proposal expires with 1 response (1 approval). Adjusted quorum = 1, so it's executable. But if a second member then rejects (after deadline), `responded` becomes 2, and `adjustedQuorum = ceil(3*2/5) = 2`. Now 1 approval < 2 required. The proposal flips from executable to non-executable. A race condition exists between late responses and execution.

Conversely, a late approval could make a previously non-executable proposal executable.

**Recommendation:** Either enforce the deadline in `approve()`/`reject()` (`if (block.timestamp > p.deadline) revert DeadlineReached();`), or snapshot `responseCount` at the deadline.

#### 23-3. StakeBoard: `responseWindow` can be set to zero

| Field    | Value |
|----------|-------|
| Severity | Medium |
| File     | `contracts/src/StakeBoard.sol` |
| Location | `setResponseWindow()` and constructor |

**Description:** The `setResponseWindow()` function (callable only via board proposal) has no minimum value check. Setting `responseWindow = 0` causes `deadline = createdAt + 0`, meaning every proposal's deadline is in the past at the moment of creation. This immediately triggers the adjusted quorum path in `execute()`, and since the proposer auto-approves (setting `responded = 1, approvalCount = 1`), a single member can propose and execute in the same transaction.

The constructor also accepts `responseWindow_ = 0` without validation.

**Recommendation:** Add `require(newWindow >= MIN_RESPONSE_WINDOW)` with a reasonable minimum (e.g., 1 day).

#### 23-4. StakeBoard: `cancel()` uses wrong error type

| Field    | Value |
|----------|-------|
| Severity | Informational |
| File     | `contracts/src/StakeBoard.sol` |
| Location | `cancel()`, line `if (msg.sender != p.proposer) revert NotMember();` |

**Description:** When a non-proposer tries to cancel a proposal, `NotMember()` is reverted. The error should be `Unauthorized()` or a new `NotProposer()` error, since the caller may indeed be a member — they're just not the proposer.

#### 23-5. StakeBoard: `execute()` is callable by anyone, including non-members

| Field    | Value |
|----------|-------|
| Severity | Low |
| File     | `contracts/src/StakeBoard.sol` |
| Location | `execute()` function |

**Description:** The `execute()` function has no access control — any address can call it. While the function only succeeds if quorum conditions are met (which requires member approvals), allowing external callers means a frontrunner could execute a proposal at a strategically chosen moment (e.g., immediately after deadline to exploit the adjusted quorum before additional members respond).

This is documented behavior ("Can be called by anyone once conditions are met") but has implications when combined with finding 23-2.

#### 23-6. StakeBoard: Missing reentrancy guard on `execute()`

| Field    | Value |
|----------|-------|
| Severity | Low |
| File     | `contracts/src/StakeBoard.sol` |
| Location | `execute()` function |

**Description:** The `execute()` function performs an external call (`target.call(p.data)`) after setting `p.executed = true`. While the checks-effects-interactions pattern is followed (state is updated before the call), there is no `ReentrancyGuard`. If the target contract's function triggers a callback (e.g., via token transfer hooks), a reentrant call to `execute()` on a different proposal could succeed in the same transaction. In practice, the target is `StakeCertificates` which doesn't have callback-triggering operations, so the risk is low.

#### 23-7. `RecipientNotSmartWallet` check may block legitimate use cases

| Field    | Value |
|----------|-------|
| Severity | Medium |
| File     | `contracts/src/StakeCertificates.sol` |
| Location | `issueClaim()` and `issueClaimBatch()`, check `if (to.code.length == 0) revert RecipientNotSmartWallet();` |

**Description:** Claims can now only be issued to addresses with deployed code (smart contract wallets). This has several implications:

1. **EOAs permanently excluded.** Any stakeholder using a standard Ethereum account (MetaMask, hardware wallet) cannot receive claims directly. They must first deploy a smart contract wallet.
2. **CREATE2 counterfactual wallets fail.** If a wallet address is computed via CREATE2 but not yet deployed, `code.length` is 0 and the check fails.
3. **Deployment order dependency.** During the constructor of a smart wallet, `code.length` is 0. If claim issuance somehow occurs within a constructor, it would fail.

While requiring smart wallets may be a deliberate design choice for key recovery purposes, it significantly narrows the user base and creates a deployment ordering dependency.

**Recommendation:** Document this requirement prominently. Consider whether the check should be optional per-pact or whether EOA support is truly unnecessary.

#### 23-8. Unlimited dilution via `governanceMint` + `setAuthorizedSupply`

| Field    | Value |
|----------|-------|
| Severity | Medium |
| File     | `contracts/src/StakeToken.sol` |
| Location | `governanceMint()` and `setAuthorizedSupply()` |

**Description:** The `GOVERNANCE_ROLE` holder can call `setAuthorizedSupply()` to raise the supply cap and then `governanceMint()` to mint tokens up to the new cap. Since both functions require the same role and there's no timelock between cap raise and mint, governance can dilute all token holders instantly and without limit.

The override mechanism in `StakeVault` (50%+1 votes, 20% quorum) provides a check, but if governance itself is compromised, dilution can occur before an override proposal can pass (which requires a voting period).

**Recommendation:** Consider adding a timelock between `setAuthorizedSupply` and `governanceMint`, or requiring supermajority for supply increases, or limiting the maximum single supply increase.

#### 23-9. Unused error declaration: `NothingToRedeem`

| Field    | Value |
|----------|-------|
| Severity | Informational |
| File     | `contracts/src/StakeCertificates.sol` |
| Location | Line 42, `error NothingToRedeem();` |

**Description:** The `NothingToRedeem` error is declared but never used in any function. This is dead code.

#### 23-10. `redeemToStake` no longer validates `unitType` from caller

| Field    | Value |
|----------|-------|
| Severity | Informational |
| File     | `contracts/src/StakeCertificates.sol` |
| Location | `redeemToStake()` |

**Description:** Previously, the caller passed a `unitType` parameter that was validated against the claim's `unitType` (`if (unitType != c.unitType) revert InvalidUnits()`). Now, `unitType` is automatically taken from the claim (`c.unitType`). While this removes a potential source of user error and is arguably better, the idempotency hash now uses fewer parameters (`keccak256(abi.encode(claimId, units, reasonHash))`), meaning two redemptions with different reason hashes against the same claim/units will have different hashes. This is correct behavior.

#### 23-11. Stake burn function bypasses pause

| Field    | Value |
|----------|-------|
| Severity | Low |
| File     | `contracts/src/StakeCertificates.sol` |
| Location | `SoulboundStake.burn()` |

**Description:** The `burn()` function on `SoulboundStake` has no `whenNotPaused` modifier. A holder can burn their stake even when the contracts are paused. The test `test_BurnStake_WorksWhenPaused` confirms this is intentional behavior ("it's their property"). However, this means during an emergency pause (potentially to investigate fraud or errors), holders could destroy evidence by burning stakes.

#### 23-12. Architectural change: Stakes are now irrevocable

| Field    | Value |
|----------|-------|
| Severity | Informational |
| File     | `contracts/src/StakeCertificates.sol`, `contracts/src/StakeVault.sol` |

**Description:** This PR fundamentally changes the trust model:

- **Before:** Stakes had vesting schedules and could be revoked (UNVESTED_ONLY or ANY modes).
- **After:** Stakes are unconditional ownership. No vesting, no revocation. Only the holder can burn.

Vesting and revocation now happen entirely at the Claim layer. Once a Claim is redeemed to a Stake, the authority has zero recourse. This is documented as intentional ("A Stake is a fact") but has implications:

1. Any error at the redemption step is permanent. If `redeemToStake` is called with wrong parameters, the resulting Stake cannot be corrected.
2. The authority's only recourse for post-Stake fraud is off-chain legal action.
3. The `StakeVault` is greatly simplified (no `releaseVestedTokens`, no vesting calculations, 1:1 token conversion), which reduces smart contract attack surface.

This is a defensible design choice documented extensively in `DESIGN.md`.

#### 23-13. `StakeVault.startSeatAuction()` missing `nonReentrant`

| Field    | Value |
|----------|-------|
| Severity | Low |
| File     | `contracts/src/StakeVault.sol` |
| Location | `startSeatAuction()` |

**Description:** The `startSeatAuction()` function is the only state-modifying auction function without a `nonReentrant` modifier. While it doesn't make external calls (it only reads `stakeContract.ownerOf()` and writes storage), the inconsistency with `bidForSeat()`, `settleAuction()`, and `reclaimSeat()` (all of which have `nonReentrant`) is notable.

---

## Summary

| PR  | Critical | High | Medium | Low | Informational |
|-----|----------|------|--------|-----|---------------|
| #18 | 0 | 0 | 0 | 1 | 3 |
| #19 | 0 | 0 | 1 | 0 | 1 |
| #20 | 0 | 0 | 0 | 0 | 1 |
| #21 | 0 | 0 | 0 | 0 | 3 |
| #22 | 0 | 0 | 0 | 0 | 1 |
| #23 | 0 | 1 | 3 | 3 | 6 |
| **Total** | **0** | **1** | **4** | **4** | **15** |

### Key Recommendations

1. **StakeBoard adjusted quorum (23-1, High):** The most significant finding. A single board member can unilaterally execute proposals when others don't respond. Add a minimum absolute quorum floor.
2. **StakeBoard deadline enforcement (23-2, Medium):** Enforce response deadlines in `approve()`/`reject()` to prevent race conditions.
3. **StakeBoard response window minimum (23-3, Medium):** Prevent `responseWindow = 0` which collapses governance entirely.
4. **Role revocation completeness (19-1, Medium):** Consider adding `whenNotTransitioned` to all authority-gated functions or tracking role grants.
5. **Governance dilution controls (23-8, Medium):** Consider a timelock between supply cap increase and mint to prevent instant dilution by compromised governance.
