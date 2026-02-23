# Smart Contract Security Audit Report

**Scope:** StakeCertificates.sol, StakeToken.sol, StakeVault.sol, StakeBoard.sol, ProtocolFeeLiquidator.sol  
**Compiler:** Solidity ^0.8.24  
**Date:** 2026-02-23  

---

## Executive Summary

This audit covers five Solidity contracts forming a soulbound certificate + token + governance system. The system lifecycle proceeds from Pact creation → Claim issuance (with vesting) → Stake minting (unconditional ownership) → Token transition → Governance seat auctions.

**27 findings** were identified:  
- **Critical:** 1  
- **High:** 4  
- **Medium:** 5  
- **Low:** 12  
- **Informational:** 5  

---

## Critical Findings

### C-01: Governor Can Burn Governance Seat Certificate — Permanent DoS on Override and Reclaim

**Contract:** `SoulboundStake` / `StakeVault`  
**Functions:** `SoulboundStake.burn()`, `StakeVault.reclaimSeat()`, `StakeVault.executeOverride()`  
**Lines:** SoulboundStake L699-705; StakeVault L375-394, L452-467  
**Severity:** Critical  

**Description:**  
After winning a governance seat auction, the governor receives ownership of the soulbound stake certificate via `settleAuction()` (StakeVault L364). The `SoulboundStake.burn()` function allows any token holder to permanently destroy their stake with no access-control restriction beyond ownership:

```solidity
function burn(uint256 stakeId) external {
    if (ownerOf(stakeId) != msg.sender) revert NotHolder();
    delete _stakes[stakeId];
    delete stakePact[stakeId];
    _burn(stakeId);
    emit StakeBurned(stakeId, msg.sender);
}
```

A malicious governor can burn the certificate they received. This has cascading, irreversible consequences:

1. **`reclaimSeat(certId)` permanently reverts:** It attempts `stakeContract.transferFrom(formerGovernor, address(this), certId)` on a nonexistent token. OpenZeppelin v5's `transferFrom` calls `_update` which returns `previousOwner = address(0)`, then reverts with `ERC721IncorrectOwner` because `address(0) != formerGovernor`.

2. **`executeOverride()` permanently reverts:** The override loop iterates all `depositedStakeIds` and calls `transferFrom` for every active seat. A single burned certificate causes the entire transaction to revert (no try/catch), permanently blocking the "nuclear option" governance mechanism for ALL seats.

3. **`totalGovernanceWeight` is permanently inflated:** The burned cert's units are never subtracted from `totalGovernanceWeight` since neither `reclaimSeat` nor `executeOverride` can complete.

4. **Bid tokens are locked forever:** The governor's bid amount can never be returned since `reclaimSeat` cannot execute.

5. **Irreversible:** `SoulboundStake._vault` is set once via `setVault()` (L126-130), so a new vault cannot be authorized. The system is permanently bricked for that seat.

**Proof of Concept:**
```
1. Attacker bids on governance seat auction for certId=5, wins.
2. settleAuction(5) transfers cert #5 to attacker, sets seats[5].active = true.
3. Attacker calls SoulboundStake.burn(5) — cert #5 is destroyed.
4. Anyone calls reclaimSeat(5) → reverts (token doesn't exist).
5. Override proposal passes vote → executeOverride() loops over all deposited
   stakes, hits certId=5 with seat.active == true, calls transferFrom on
   nonexistent token → entire transaction reverts.
6. ALL governance seats are now unrecoverable. Override mechanism is dead.
```

**Recommendation:**  
Add a governance-aware burn restriction in `SoulboundStake.burn()`:
```solidity
function burn(uint256 stakeId) external {
    if (ownerOf(stakeId) != msg.sender) revert NotHolder();
    if (_vault != address(0)) revert BurnDisabledPostTransition();
    // ...
}
```
Or: have `executeOverride()` and `reclaimSeat()` use try/catch around the `transferFrom` call and handle the burned-token case gracefully by marking the seat inactive without attempting transfer.

---

## High Findings

### H-01: Flash Loan Governance Attack on Override Voting

**Contract:** `StakeVault`  
**Function:** `voteOverride()`  
**Lines:** StakeVault L416-431  
**Severity:** High  

**Description:**  
Override vote weight is determined by `token.governanceBalance(msg.sender)` at the instant of the `voteOverride()` call — there is no snapshot mechanism:

```solidity
uint256 weight = token.governanceBalance(msg.sender);
if (weight == 0) revert Unauthorized();
p.hasVoted[msg.sender] = true;
if (support) p.votesFor += weight;
```

An attacker can use a flash loan to temporarily acquire a massive StakeToken position, cast a vote with outsized weight, then return the tokens in the same transaction. The `hasVoted` mapping prevents double-voting from the same address but does not prevent a single flash-loan-amplified vote.

**Attack Scenario:**
```
1. Override proposal is active (within votingEnd).
2. Attacker flash-borrows ETH/stablecoin.
3. Swaps for StakeTokens on a DEX (large position).
4. Calls voteOverride(proposalId, true) — weight = entire borrowed position.
5. Swaps StakeTokens back, repays flash loan.
6. Net cost: flash loan fee. Net effect: potentially decisive vote.
```

**Recommendation:**  
Implement an ERC20Votes-style checkpoint/snapshot mechanism so voting weight is locked at proposal creation time, not at vote time. Alternatively, require tokens to be staked/locked for a minimum period before being eligible for voting.

---

### H-02: StakeBoard Single-Member Execution After Response Window

**Contract:** `StakeBoard`  
**Function:** `execute()`  
**Lines:** StakeBoard L210-250  
**Severity:** High  

**Description:**  
After the response deadline, the quorum is adjusted proportionally to the number of responding members. This allows a single member to unilaterally execute proposals if no other members respond:

```solidity
adjustedQuorum = (quorum * responded + totalMembers - 1) / totalMembers;
if (adjustedQuorum == 0) adjustedQuorum = 1;
```

**Proof of Concept:**
```
Board: 5 members, quorum = 3, responseWindow = 7 days.
1. Member A proposes. Auto-approves: approvalCount=1, responseCount=1.
2. No other member responds within 7 days (vacation, lost keys, etc.).
3. After deadline: adjustedQuorum = ceil(3 * 1 / 5) = ceil(0.6) = 1.
4. approvals (1) >= adjustedQuorum (1) → passes.
5. Single member executes a proposal that normally requires 3/5 approval.
```

This fundamentally undermines the multisig security model. A malicious or compromised single member can wait for a quiet period and execute arbitrary proposals against the target contract (StakeCertificates), including issuing claims, amending pacts, or initiating transition.

**Recommendation:**  
Enforce a minimum adjusted quorum regardless of response count, e.g., `if (adjustedQuorum < 2 && members.length > 1) revert QuorumNotMet()`. Alternatively, require at least a majority of members to respond before allowing post-deadline execution.

---

### H-03: transferAuthority Self-Transfer Bricks StakeCertificates

**Contract:** `StakeCertificates`  
**Function:** `transferAuthority()`  
**Lines:** StakeCertificates L792-809  
**Severity:** High  

**Description:**  
If `transferAuthority()` is called with the current authority's own address (`transferAuthority(authority)`), the function grants roles that are already held (no-op in OpenZeppelin) and then revokes all roles from the same address:

```solidity
address oldAuthority = authority;
authority = newAuthority; // same address

_grantRole(DEFAULT_ADMIN_ROLE, newAuthority);  // already held → no-op
_grantRole(AUTHORITY_ROLE, newAuthority);       // already held → no-op
_grantRole(PAUSER_ROLE, newAuthority);          // already held → no-op

_revokeRole(DEFAULT_ADMIN_ROLE, oldAuthority);  // oldAuthority == newAuthority → revoked!
_revokeRole(AUTHORITY_ROLE, oldAuthority);       // revoked!
_revokeRole(PAUSER_ROLE, oldAuthority);          // revoked!
```

The result is that the authority permanently loses ALL roles. Since `DEFAULT_ADMIN_ROLE` is also revoked, no one can grant new roles. The contract becomes permanently ungovernable — no claims can be issued, no pacts created, no transition initiated. Child contracts (CLAIM, STAKE, REGISTRY) are also effectively bricked since their admin (StakeCertificates) can no longer invoke role-gated functions.

**Recommendation:**  
Add a check: `if (newAuthority == authority) revert InvalidAuthority();`

---

### H-04: executeOverride DoS via Unbounded Loop Over depositedStakeIds

**Contract:** `StakeVault`  
**Function:** `executeOverride()`  
**Lines:** StakeVault L452-467  
**Severity:** High  

**Description:**  
`executeOverride()` iterates over the entire `depositedStakeIds` array:

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

The `depositedStakeIds` array grows without bound via `processTransitionBatch()` (L217: `depositedStakeIds.push(stakeId)`). If thousands of stakes are processed over multiple batches, the loop could exceed the block gas limit, making override execution permanently impossible regardless of governance votes.

Each iteration involves at least one `SLOAD` for the seat lookup. Active seats also incur two external calls (`transferFrom` + `token.transfer`), each costing ~30k+ gas. With 1000+ deposited stakes and even a handful of active seats, gas costs could exceed 30M gas.

**Recommendation:**  
Redesign override execution to be batch-processable, or maintain a separate linked list / set of active governance seat IDs to iterate only over active seats rather than all deposited stakes.

---

## Medium Findings

### M-01: vestStart=0 With Non-Zero vestEnd Bypasses Intended Vesting Schedule

**Contract:** `SoulboundClaim`  
**Function:** `issueClaim()`, `_calculateVestedUnits()`  
**Lines:** StakeCertificates L441-443, L604-620  
**Severity:** Medium  

**Description:**  
The vesting validation only checks ordering when `vestEnd != 0`:

```solidity
if (vestEnd != 0) {
    if (!(vestStart <= vestCliff && vestCliff <= vestEnd)) revert InvalidVesting();
}
```

This allows `vestStart = 0` with non-zero `vestCliff` and `vestEnd`. In `_calculateVestedUnits`, the calculation becomes:

```solidity
uint256 elapsed = timestamp - c.vestStart; // timestamp - 0 = timestamp (~1.7 billion)
uint256 duration = c.vestEnd - c.vestStart; // vestEnd - 0 = vestEnd
return (c.maxUnits * elapsed) / duration;
```

If `vestEnd` is set to a future timestamp (e.g., `block.timestamp + 365 days`), then `elapsed / duration` would be approximately `1700000000 / 1731000000 ≈ 0.98`, meaning ~98% of units would be immediately vested at the time of issuance — defeating the purpose of the vesting schedule entirely.

**Recommendation:**  
Add validation: `if (vestEnd != 0 && vestStart == 0) revert InvalidVesting();` or require `vestStart >= block.timestamp` when `vestEnd != 0`.

---

### M-02: No Slippage Protection in ProtocolFeeLiquidator

**Contract:** `ProtocolFeeLiquidator`  
**Function:** `liquidate()`  
**Lines:** ProtocolFeeLiquidator L146-159  
**Severity:** Medium  

**Description:**  
The `liquidate()` function calls the router with no minimum output amount:

```solidity
proceeds = ILiquidationRouter(router).liquidate(token, tokensSold, treasury);
```

There is no `minAmountOut` parameter. MEV bots can sandwich the liquidation transaction:
1. Front-run: sell tokens to crash price.
2. Liquidation executes at depressed price.
3. Back-run: buy back at the depressed price.

Since `liquidate()` is permissionless, an attacker can time their sandwich attack precisely. The protocol treasury receives significantly less value than the tokens are worth.

**Recommendation:**  
Add a `minAmountOut` parameter to `liquidate()` and pass it through to the router. Alternatively, implement TWAP-based price checks.

---

### M-03: Front-Running / MEV in Governance Seat Auctions

**Contract:** `StakeVault`  
**Function:** `bidForSeat()`  
**Lines:** StakeVault L317-338  
**Severity:** Medium  

**Description:**  
Governance seat auctions use a simple highest-bidder model where bids are visible in the mempool. An attacker can:

1. Monitor the mempool for `bidForSeat` transactions.
2. Front-run with a bid that is exactly `1 wei` higher.
3. Win the auction at minimal premium.

Additionally, there is no auction sniping protection (no time extension on late bids). A bidder can wait until the final block before `endTime` and submit a winning bid, giving other participants no time to respond.

**Recommendation:**  
Implement a sealed-bid (commit-reveal) auction, add anti-sniping time extensions, or use a Vickrey (second-price) auction mechanism.

---

### M-04: Unredeemed Claims Become Worthless After Transition

**Contract:** `StakeCertificates`  
**Function:** `redeemToStake()`, `initiateTransition()`  
**Lines:** StakeCertificates L831-851, L1017-1059  
**Severity:** Medium  

**Description:**  
`redeemToStake()` has the `whenNotTransitioned` modifier. After `initiateTransition()` is called, no more claims can be redeemed to stakes. Claims with vesting schedules extending past the transition date lose all unvested (and even vested-but-unredeemed) units permanently.

There is no protective mechanism to ensure all vested claims are redeemed before transition, no grace period for claim holders, and no warning event emitted. The authority can initiate transition at any time while claims are still vesting, effectively expropriating claim holders' vested-but-unredeemed units.

**Recommendation:**  
Add a pre-transition check that verifies no outstanding redeemable claim units exist, or provide a post-transition redemption path.

---

### M-05: Operator Retains Permanent DEFAULT_ADMIN_ROLE on StakeVault

**Contract:** `StakeVault`  
**Function:** `constructor()`  
**Lines:** StakeVault L171-172  
**Severity:** Medium  

**Description:**  
The vault constructor grants `DEFAULT_ADMIN_ROLE` and `OPERATOR_ROLE` to `operator_`:

```solidity
_grantRole(DEFAULT_ADMIN_ROLE, operator_);
_grantRole(OPERATOR_ROLE, operator_);
```

There is no mechanism to revoke these roles after transition is complete. The operator permanently retains the ability to:
- Grant `OPERATOR_ROLE` to additional addresses.
- Grant `DEFAULT_ADMIN_ROLE` to additional addresses.
- Call `processTransitionBatch()` with new stake IDs (if any exist).
- Call `deployLiquidator()` (one-time, but timing is controlled).

This contradicts the system's philosophy that "issuer powers freeze permanently" after transition. The vault operator remains an omnipotent centralization risk.

**Recommendation:**  
Add a function to renounce `DEFAULT_ADMIN_ROLE` after transition is complete, or have the transition process automatically revoke the operator's admin role.

---

## Low Findings

### L-01: RecipientNotSmartWallet Check Bypassable

**Contract:** `StakeCertificates`  
**Function:** `issueClaim()`, `issueClaimBatch()`  
**Lines:** StakeCertificates L921, L962  
**Severity:** Low  

**Description:**  
`if (to.code.length == 0) revert RecipientNotSmartWallet();` can be bypassed if the recipient contract calls during its constructor (when `code.length == 0`). It also fails to protect against CREATE2-deployed contracts that are later self-destructed. The check provides a false sense of security.

---

### L-02: reasonHash Overwritten on Partial Redemptions

**Contract:** `SoulboundClaim`  
**Function:** `recordRedemption()`  
**Lines:** StakeCertificates L574-575  
**Severity:** Low  

**Description:**  
`c.reasonHash = reasonHash;` overwrites the previous reason hash on every partial redemption. For claims that are redeemed in multiple tranches, only the last tranche's reason is preserved on-chain. Earlier redemption reasons are lost from the on-chain state (though still available via event logs).

---

### L-03: burn() Callable When Contract Is Paused

**Contract:** `SoulboundStake`  
**Function:** `burn()`  
**Lines:** StakeCertificates L699-705  
**Severity:** Low  

**Description:**  
`burn()` has no `whenNotPaused` modifier. The `_update` override only checks `_requireNotPaused()` for transfers (where `from != address(0) && to != address(0)`). Burns pass through without the pause check. A holder can burn their stake even when the contract is paused.

---

### L-04: No Validation on Pact Authority Address

**Contract:** `StakePactRegistry`  
**Function:** `createPact()`  
**Lines:** StakeCertificates L292-325  
**Severity:** Low  

**Description:**  
The `authority` parameter in `createPact()` is not validated against `address(0)`. A pact can be created with `authority = address(0)`, which would make the pact's authority meaningless.

---

### L-05: Amended Pact Does Not Invalidate Old Pact

**Contract:** `StakePactRegistry`  
**Function:** `amendPact()`  
**Lines:** StakeCertificates L330-364  
**Severity:** Low  

**Description:**  
When a pact is amended, the old pact remains active in the `_pacts` mapping. New claims can still be issued referencing the old (superseded) pact ID. There is no mechanism to mark the old pact as deprecated or prevent new claims against it.

---

### L-06: execute() Swallows Revert Data

**Contract:** `StakeBoard`  
**Function:** `execute()`  
**Lines:** StakeBoard L246-247  
**Severity:** Low  

**Description:**  
```solidity
(bool success,) = target.call(p.data);
if (!success) revert ExecutionFailed();
```
The return data (including revert reason) is discarded. When the target call fails, the board receives only a generic `ExecutionFailed()` error with no indication of why the target call reverted. This makes debugging failed proposals difficult.

**Recommendation:**  
Bubble up the revert data using assembly or use `Address.functionCall()`.

---

### L-07: StakeToken Constructor Missing Zero-Address Checks

**Contract:** `StakeToken`  
**Function:** `constructor()`  
**Lines:** StakeToken L45-75  
**Severity:** Low  

**Description:**  
`vault_` and `governance_` parameters are not checked against `address(0)`. If either is zero:
- `vault_ == address(0)`: MINTER_ROLE granted to zero address, no one can mint.
- `governance_ == address(0)`: GOVERNANCE_ROLE and DEFAULT_ADMIN_ROLE granted to zero address; governance is bricked.

---

### L-08: governanceMint Bypasses Lockup Restrictions

**Contract:** `StakeToken`  
**Function:** `governanceMint()`  
**Lines:** StakeToken L109-112  
**Severity:** Low  

**Description:**  
`governanceMint()` mints tokens to any address without setting a lockup period. Unlike tokens minted during `processTransitionBatch()` (which set `holderLockupEnd`), governance-minted tokens are immediately transferable. This creates an asymmetry between transition-era and governance-era token holders.

---

### L-09: Lockup Timing Unfairness Across Transition Batches

**Contract:** `StakeVault`  
**Function:** `processTransitionBatch()`  
**Lines:** StakeVault L197, L226-230  
**Severity:** Low  

**Description:**  
`lockupEnd` is calculated as `uint64(block.timestamp) + lockupDuration` at the time each batch is processed. Holders in later batches receive later lockup end times. The operator controls batch ordering and timing, creating the ability to selectively disadvantage holders by delaying their batch processing.

A holder's lockup end is only set on first encounter (`if (holderLockupEnd[holder] == 0)`), so a holder appearing in multiple batches keeps their first lockup timestamp. However, the operator still controls which holders appear in the first batch.

---

### L-10: setAuthorizedSupply Allows Decreasing Supply Cap

**Contract:** `StakeToken`  
**Function:** `setAuthorizedSupply()`  
**Lines:** StakeToken L96-101  
**Severity:** Low  

**Description:**  
`setAuthorizedSupply()` only checks `newSupply < totalSupply()`, not `newSupply < authorizedSupply`. Governance can reduce the authorized supply to just above `totalSupply()`, effectively preventing any future minting (including `governanceMint`). While this requires a governance vote, it could be used as a griefing vector by a governance majority to freeze out minority holders from future dilution protection.

---

### L-11: Zero Minimum Bid Possible Due to Integer Division

**Contract:** `StakeVault`  
**Function:** `bidForSeat()`  
**Lines:** StakeVault L323-325  
**Severity:** Low  

**Description:**  
```solidity
uint256 minBid = (s.units * auctionMinBidBps) / BPS_BASE;
```
For stakes with very small `units` values (e.g., `units = 9` with `auctionMinBidBps = 1000`), integer division results in `minBid = 0`. This allows governance seats to be acquired for free (0 tokens).

---

### L-12: responseWindow=0 Enables Instant Quorum Bypass

**Contract:** `StakeBoard`  
**Function:** `setResponseWindow()`  
**Lines:** StakeBoard L321-325  
**Severity:** Low  

**Description:**  
`setResponseWindow()` does not enforce a minimum value. If set to 0, every proposal's deadline is `block.timestamp`, meaning the "after deadline" branch with adjusted quorum is immediately active. Combined with H-02 (single-member execution), this allows a single board member to propose and execute in the same block.

This requires a board vote to set `responseWindow = 0`, but once set, the lowered security persists for all future proposals.

---

## Informational Findings

### I-01: Protocol Fee Rounding Down for Small Batches

**Contract:** `StakeVault`  
**Function:** `processTransitionBatch()`  
**Lines:** StakeVault L235  
**Severity:** Informational  

**Description:**  
`uint256 protocolFee = (totalMinted * PROTOCOL_FEE_BPS) / BPS_BASE;` rounds down. For batches where `totalMinted < 100`, the protocol fee is 0. Processing many small batches instead of one large batch results in less total protocol fee collected.

---

### I-02: cancel() Uses Wrong Error

**Contract:** `StakeBoard`  
**Function:** `cancel()`  
**Lines:** StakeBoard L259  
**Severity:** Informational  

**Description:**  
```solidity
if (msg.sender != p.proposer) revert NotMember();
```
The `NotMember()` error is semantically incorrect. The check verifies that the caller is the proposer, not that they are a board member. A dedicated `NotProposer()` error would be more appropriate and aid in off-chain error handling.

---

### I-03: Vesting Calculation Theoretical Overflow for Extreme maxUnits

**Contract:** `SoulboundClaim`  
**Function:** `_calculateVestedUnits()`  
**Lines:** StakeCertificates L619  
**Severity:** Informational  

**Description:**  
`(c.maxUnits * elapsed) / duration` could overflow if `maxUnits` is extremely large (approaching `2^192` or higher, since `elapsed` can be up to ~`2^64`). While Solidity 0.8+ reverts on overflow, an extremely large `maxUnits` value would make vesting calculations permanently revert, locking the claim. For practical token amounts this is not an issue, but there is no upper bound enforced on `maxUnits`.

---

### I-04: onERC721Received Allows Unsolicited NFT Deposits

**Contract:** `StakeVault`  
**Function:** `onERC721Received()`  
**Lines:** StakeVault L495-497  
**Severity:** Informational  

**Description:**  
The vault unconditionally returns the correct selector for `onERC721Received`, accepting any ERC-721 token sent via `safeTransferFrom`. This means arbitrary NFTs (not just stake certificates) can be deposited into the vault with no tracking or recovery mechanism. These tokens would be permanently locked.

---

### I-05: Token Approval Not Reset After Liquidation

**Contract:** `ProtocolFeeLiquidator`  
**Function:** `liquidate()`  
**Lines:** ProtocolFeeLiquidator L153  
**Severity:** Informational  

**Description:**  
```solidity
IERC20(token).approve(router, tokensSold);
```
If the router does not consume the full approved amount, the residual allowance persists. While `approve` replaces (not adds to) the previous allowance, a malicious or buggy router could exploit the outstanding allowance between `liquidate()` calls. The router is immutable and trusted, so practical risk is low.

**Recommendation:**  
Reset approval to 0 after the `liquidate` call: `IERC20(token).approve(router, 0);`

---

## Summary Table

| ID | Severity | Contract | Finding |
|----|----------|----------|---------|
| C-01 | Critical | SoulboundStake / StakeVault | Governor burns seat cert → permanent DoS on override + reclaim |
| H-01 | High | StakeVault | Flash loan governance attack on override voting |
| H-02 | High | StakeBoard | Single-member execution after response window |
| H-03 | High | StakeCertificates | transferAuthority self-transfer bricks contract |
| H-04 | High | StakeVault | Unbounded loop DoS in executeOverride |
| M-01 | Medium | SoulboundClaim | vestStart=0 bypasses intended vesting schedule |
| M-02 | Medium | ProtocolFeeLiquidator | No slippage protection in liquidate() |
| M-03 | Medium | StakeVault | Front-running / MEV in seat auctions |
| M-04 | Medium | StakeCertificates | Unredeemed claims lost after transition |
| M-05 | Medium | StakeVault | Operator retains permanent admin role |
| L-01 | Low | StakeCertificates | Smart wallet check bypassable |
| L-02 | Low | SoulboundClaim | reasonHash overwritten on partial redemptions |
| L-03 | Low | SoulboundStake | burn() callable when paused |
| L-04 | Low | StakePactRegistry | No authority address validation |
| L-05 | Low | StakePactRegistry | Old pact not invalidated after amendment |
| L-06 | Low | StakeBoard | execute() swallows revert data |
| L-07 | Low | StakeToken | Constructor missing zero-address checks |
| L-08 | Low | StakeToken | governanceMint bypasses lockup |
| L-09 | Low | StakeVault | Lockup timing unfairness across batches |
| L-10 | Low | StakeToken | setAuthorizedSupply allows decreasing cap |
| L-11 | Low | StakeVault | Zero minimum bid via integer division |
| L-12 | Low | StakeBoard | responseWindow=0 enables quorum bypass |
| I-01 | Info | StakeVault | Protocol fee rounding for small batches |
| I-02 | Info | StakeBoard | cancel() uses wrong error |
| I-03 | Info | SoulboundClaim | Theoretical overflow for extreme maxUnits |
| I-04 | Info | StakeVault | onERC721Received accepts arbitrary NFTs |
| I-05 | Info | ProtocolFeeLiquidator | Token approval not reset after liquidation |
