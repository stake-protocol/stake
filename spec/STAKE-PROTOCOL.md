# Stake Protocol — Soulbound Equity Certificates

Status: Draft v0.2

## 1. Abstract

Stake Protocol defines an onchain standard for issuing, managing, and optionally transitioning non-transferable equity certificates as verifiable, wallet-held records. The protocol models a deterministic lifecycle: **Pact → Claim → Stake → Token (optional)**. A Pact is the canonical, versioned agreement that defines rights, issuer powers, amendment rules, revocation rules, and dispute terms. A Claim is a contingent certificate issued under a Pact. A Stake is the realized certificate after conversion from a Claim. When elected, the protocol provides a Transition mechanism that converts certificates into ERC-20 tokens, freezes issuer powers, and activates a seat-based governance system.

The standard is designed to minimize user actions, minimize divergence between cap table reality and chain state, and place operational burden on the issuer. Pre-transition, the issuer governs. Post-transition, governance transfers to certificate holders (governance seats) and token holders (economic voting), and issuer powers freeze permanently.

## 2. Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119.

**Issuer**: The issuing entity, corporation, company, DAO, BORG, project or protocol.

**Authority**: The onchain address set authorized to issue, amend, convert, revoke, or void under an Issuer. Default implementation uses a multisig.

**Pact**: **P**lain **A**greement for **C**ontract **T**erms. A versioned, content-addressed agreement that defines rights and lifecycle rules.

**Claim**: A non-transferable certificate representing a contingent right to receive a Stake under a Pact.

**Stake**: A non-transferable certificate representing an issued ownership position under a Pact.

**Void**: A terminal state marking a certificate as cancelled without erasing history.

**Revoke**: Cancellation of unvested or cancellable portions per Pact rules. On revocation, the implementation MUST snapshot the vested amount and reduce units to the vested quantity.

**Redeem**: Conversion of a Claim to a Stake certificate.

**Amend**: Creating a new Pact version, optionally binding future issuances and optionally affecting existing certificates only if the Pact explicitly allows it.

**Transition**: The optional, irreversible event that converts a certificate-based private structure into a token-based public one. Issuer powers freeze permanently at transition. All certificates are transferred to the Vault and ERC-20 tokens are minted.

**Vault**: The smart contract that custodies deposited certificates post-transition, manages the certificate-to-token relationship, administers governance seat auctions, and enforces forced reclaim at term end.

**Governor**: A token holder who has won a governance seat via auction and holds a certificate in their wallet for the duration of their term.

**Term**: A fixed governance period (configurable, default 1 year) after which a governance seat returns to the Vault for re-auction.

**Override**: Emergency mechanism allowing token holders to replace all governors. Threshold: 50%+1 of votes cast, 20% quorum of total token supply.

**Authorized Supply**: The hard cap on total token supply, set at transition. Changeable only by token holder supermajority vote.

## 3. Design Goals

The standard optimizes for three properties.

First, evidentiary clarity. The chain MUST carry a self-describing reference to the Pact version and rights bundle that defines "what the holder is supposed to have."

Second, minimal state and minimal user actions. The issuer confirms funding and the protocol mints immediately; recipients never need to pay gas to receive certificates.

Third, controlled flexibility. By default the issuer MAY revoke and amend within explicit Pact rules, while projects MAY opt into immutability by disabling those powers at the Pact level.

## 4. Core Lifecycle

The lifecycle is deterministic.

### 4.1 Pact Creation

An Issuer defines a Pact version. The Pact has a deterministic content hash and a stable pact_id. The Pact MAY be declared mutable or immutable, and MAY define amendment authority and amendment scope.

### 4.2 Claim Issuance

All certificate issuance starts as a Claim, even for immediate issuance.

Rationale: Claim is the universal issuance envelope. It unifies "pending conversion" instruments (SAFE-like, vesting-based, milestone-based, eligibility-based) with immediate issuance (redeemable immediately). The difference is only in conversion conditions.

### 4.3 Claim Conversion

A Claim converts to a Stake via Redeem. Default flow is issuer-driven and occurs once funds or conditions are confirmed. A Claim MAY be redeemable immediately.

### 4.4 Stake Vesting and Revocation

A Stake MAY include vesting metadata. Revocation and voiding are permitted only to the extent the referenced Pact grants them.

### 4.5 Transition

An Issuer MAY initiate a Transition — the irreversible event that converts the certificate-based system into a token-based public structure. Transition is a one-way operation. Once initiated, the following changes take effect atomically:

1. All outstanding certificates are unlocked (soulbound status removed) and transferred to the Vault in a single batch operation.
2. ERC-20 tokens are minted proportional to each certificate holder's vested units.
3. All issuer powers freeze permanently. The functions `createPact`, `amendPact`, `issueClaim`, `voidClaim`, and `revokeStake` MUST revert after transition.
4. The governance system activates. Certificates in the Vault become governance seats available for auction.

Transition requires governance approval (configurable threshold, default: supermajority of certificate holders by unit-weighted vote). The `transitioned` flag, once set, MUST NOT be unset.

See §12 for the full Transition specification.

## 5. Pact Model

A Pact is the canonical source of truth for meaning and rules. Certificates reference Pact versions by pact_id.

### 5.1 Pact Identifiers

pact_id is computed as `keccak256(abi.encode(issuer_id, content_hash, keccak256(bytes(pact_version))))`.

content_hash is computed as `keccak256(canonical_pact_json_bytes)`.

canonical_pact_json_bytes MUST be computed using RFC 8785 (JSON Canonicalization Scheme, JCS).

### 5.2 Pact Fields

| Field               | Type    | Meaning                                                                                   |
| ------------------- | ------- | ----------------------------------------------------------------------------------------- |
| pact_version        | string  | Semantic version identifier                                                               |
| content_hash        | bytes32 | Hash of canonical pact JSON                                                               |
| uri                 | string  | IPFS/Arweave/HTTPS pointer to the Pact content                                            |
| issuer_id           | bytes32 | Issuer namespace                                                                          |
| authority           | address | Authority address for this Pact version                                                   |
| mutability          | uint8   | 0 = immutable, 1 = mutable per rules                                                      |
| amendment_mode      | uint8   | 0 = none, 1 = issuer_only, 2 = multisig_threshold, 3 = external_rules_hash                |
| amendment_scope     | uint8   | 0 = future_only, 1 = retroactive_allowed_if_flagged                                       |
| revocation_mode     | uint8   | 0 = none, 1 = unvested_only, 2 = per_stake_flags, 3 = external_rules_hash                 |
| dispute_law         | string  | Governing law                                                                             |
| dispute_venue       | string  | Venue                                                                                     |
| signing_mode        | uint8   | 0 = issuer_only, 1 = countersign_required_offchain, 2 = countersign_required_onchain      |
| rights_root         | bytes32 | Root hash of standardized rights schema payload                                           |
| custom_terms_hash   | bytes32 | Hash of any custom text bundle referenced by the Pact                                     |

### 5.3 Rights Schema Inside a Pact

Rights are defined in the Pact, not as a separate StakeClass object.

A Pact includes a rights payload with three top-level groups: Power, Priority, Protections. Each group is a list of ClauseInstances.

ClauseInstance canonical form is a tuple: `(clause_id, enabled, params_hash)`.

params_hash is `keccak256(canonical_params_json_bytes)` where canonical_params_json_bytes MUST be computed using RFC 8785 (JCS).

rights_root MUST be computed as `keccak256(canonical_rights_json_bytes)` where canonical_rights_json_bytes is the full rights payload JSON (including all ClauseInstances and their params objects) encoded using RFC 8785 (JCS).

This makes rights verifiable and interoperable while keeping the onchain surface small.

Power and Priority clauses are active pre-transition only. Post-transition, governance simplifies to: governance weight = certificate unit count, voting power = token balance. See §15.6.

### 5.4 Starting Clause Registry

| Clause ID         | Group       | Meaning                                  | Canonical Params                                      |
| ----------------- | ----------- | ---------------------------------------- | ----------------------------------------------------- |
| PWR_VOTE          | Power       | Voting weight and class vote requirement | weight_bps, class_vote_required                       |
| PWR_VETO          | Power       | Veto rights on enumerated actions        | actions_bitmap                                        |
| PWR_BOARD         | Power       | Board seat or appointment right          | seats, appointment_method                             |
| PWR_DELEGATE      | Power       | Delegation policy                        | allowed, max_depth                                    |
| PRI_LIQ_PREF      | Priority    | Liquidation preference                   | multiple_x_bps, seniority_rank, participating         |
| PRI_DIVIDEND      | Priority    | Dividend economics                       | rate_bps_annual, cumulative, pay_in_kind_allowed      |
| PRI_CONVERT       | Priority    | Conversion behavior                      | auto_on_exit, ratio_bps                               |
| PRO_INFO          | Protections | Information rights                       | cadence_days, scope_bitmap                            |
| PRO_PRORATA       | Protections | Pro rata participation                   | enabled, based_on_fully_diluted                       |
| PRO_ANTIDILUTION  | Protections | Anti-dilution                            | type_enum, floor_bps, cap_bps                         |
| PRO_APPROVALS     | Protections | Protective provisions approvals          | actions_bitmap, threshold_bps                         |
| PRO_MFN           | Protections | MFN upgrades                             | enabled, applies_to_terms_hash                        |
| PRO_LOCKUP        | Protections | Transfer lockup in future tokenization   | lockup_days                                           |
| PRO_PREEMPTIVE    | Protections | Preemptive rights on new issuance        | enabled, based_on_fully_diluted                       |

## 6. Certificate Model

Claims and Stakes are wallet-held ERC-721 tokens that are non-transferable during normal operation.

Each certificate MUST reference a Pact version by pact_id. The Pact carries rights_root; verifiers and indexers MUST resolve rights_root via the referenced Pact.

Certificates SHOULD expose tokenURI metadata for broad wallet/indexer compatibility. The tokenURI JSON SHOULD include issuer_id, pact_id, certificate type, and relevant hashes (conversionHash / vestingHash / revocationHash) so a third party can verify the certificate without bespoke ABI calls.

### 6.1 Unit Type Enumeration

The `unit_type` field uses the following values:

| Value | Name   | Meaning                                    |
| ----- | ------ | ------------------------------------------ |
| 0     | SHARES | Whole share units                          |
| 1     | BPS    | Basis points (10000 = 100%)                |
| 2     | WEI    | Wei-denominated fractional units           |
| 3     | CUSTOM | Custom unit type defined in Pact           |

Conforming implementations MUST store the `unit_type` on each certificate (both Claims and Stakes), not only in the Pact. This ensures that the unit domain is unambiguously readable from the certificate itself without requiring a Pact lookup.

### 6.2 Status Flags Bitfield

The `status_flags` field is a uint32 bitfield:

| Bit | Name         | Meaning                                    |
| --- | ------------ | ------------------------------------------ |
| 0   | VOIDED       | Certificate has been voided                |
| 1   | REVOKED      | Stake has been revoked                     |
| 2   | REDEEMED     | Claim has been converted to Stake          |
| 3   | DISPUTED     | Certificate is under dispute               |
| 4   | TRANSITIONED | Certificate has been deposited into Vault  |
| 5-31| Reserved     | Reserved for future use                    |

### 6.3 Claim Fields

| Field         | Type    | Meaning                                 |
| ------------- | ------- | --------------------------------------- |
| schema        | string  | claim.v1                                |
| issuer_id     | bytes32 | Issuer namespace                        |
| pact_id       | bytes32 | Pact version reference                  |
| recipient     | address | Current owner address                   |
| unit_type     | uint8   | Units domain (see 6.1)                  |
| units_max     | uint256 | Upper bound units claimable             |
| conversion    | bytes32 | Hash describing conversion rule payload |
| status_flags  | uint32  | Bitfield (see 6.2)                      |
| issued_at     | uint64  | Timestamp                               |

### 6.4 Stake Fields

| Field              | Type    | Meaning                                     |
| ------------------ | ------- | ------------------------------------------- |
| schema             | string  | stake.v1                                    |
| issuer_id          | bytes32 | Issuer namespace                            |
| pact_id            | bytes32 | Pact version reference                      |
| recipient          | address | Current owner address                       |
| unit_type          | uint8   | Units domain (see 6.1)                      |
| units              | uint256 | Issued units (reduced to vested on revoke)  |
| revoked_units      | uint256 | Units removed by revocation (0 if none)     |
| vesting            | bytes32 | Hash of vesting payload                     |
| revocation         | bytes32 | Hash of revocation payload                  |
| status_flags       | uint32  | Bitfield (see 6.2)                          |
| issued_at          | uint64  | Timestamp                                   |
| revoked_at         | uint64  | Timestamp of revocation (0 if none)         |

### 6.5 Non-Transferability and Unlock Conditions

Certificates MUST be non-transferable at the ERC-721 transfer layer during normal operation.

Certificates MUST block approvals (`approve` and `setApprovalForAll`) to prevent UX-confusing "transfer-like" flows.

Certificates MUST implement ERC-5192 (Minimal Soulbound) and MUST advertise the ERC-5192 interface via ERC-165 `supportsInterface`.

#### 6.5.1 Unlock Events

Certificates MAY be unlocked and transferred under the following protocol-level events only. These are NOT user-initiated — holders MUST NOT be able to unlock their own certificates.

| Event | Trigger | Transfer Direction | Re-lock? |
| --- | --- | --- | --- |
| Transition | Issuer calls `initiateTransition()` | All certs → Vault | Certs held by Vault, status set to TRANSITIONED |
| Governance seat award | Governor wins auction | Vault → Governor's wallet | Cert is re-locked (soulbound) for term duration |
| Governance seat reclaim | Term expires | Governor's wallet → Vault | Cert held by Vault until next auction |
| Governance seat override | Token holder override passes | All governor wallets → Vault | Certs held by Vault, emergency re-auction |

The smart contract MUST allow forced transfers by the Vault contract address regardless of the soulbound lock status. This is enforced by checking `msg.sender == vault` in the transfer hook, not by unlocking.

## 7. Funding and Minting Rules

### 7.1 Default Issuance

Issuer confirms funds or satisfaction of conditions, then mints the Claim to the recipient address, paying gas. This avoids recipient gas failures and prevents "you own it but you haven't minted it yet" ambiguity.

### 7.2 Crypto Rail Optionality

The standard permits an atomic "pay and mint" pathway as an optional application feature, but it is not required by the standard and MUST converge to the same minted Claim state.

### 7.3 Cap Table Synchronization Rule

Only minted certificates count as issued onchain positions. Executed-but-unminted agreements remain offchain state.

If funds are received but minting fails, the issuer MUST retry until the certificate is minted or the agreement is formally cancelled per the Pact.

### 7.4 Idempotence Requirement

Conforming implementations MUST be idempotent for issuance and redemption. Each issuance and redemption MUST accept an external issuance_id / redemption_id (or deterministic key) and MUST prevent double-mints under retries.

## 8. Amendments and Immutability

Amendment is a new Pact version. A Pact declares whether amendments exist, who can create them, and whether amendments MAY apply retroactively.

Default is future-only: new issuances bind to the newest Pact version the issuer chooses; existing certificates remain bound to their pact_id.

Retroactive changes are allowed only if the old Pact explicitly allows them and the new Pact carries a retroactive flag. The onchain standard does not enforce legal validity; it enforces explicitness and auditability.

Immutability is a Pact-level choice. A Pact MAY set mutability to immutable, making amendments and revocations invalid for that Pact version.

Post-transition, Pact creation and amendment MUST revert. No new Pacts may be created after transition. See §12.4.

## 9. Revocation and Voiding

Revocation is permitted only within Pact-defined modes. The standard includes the ability to mark certificates voided or revoked, and to record a reason hash.

### 9.1 Claim Voiding

Claims MAY be voided by the issuer if the Pact permits it. Pre-transition only — voiding MUST revert after transition.

### 9.2 Stake Revocation

Stakes MAY be revoked only as permitted by the Pact, typically unvested-only or per-stake flags. Pre-transition only — revocation MUST revert after transition.

When `revocation_mode` is `UNVESTED_ONLY`, revocation MUST only affect the unvested portion. The implementation MUST:

1. Calculate the vested amount at the time of revocation:

```
if (block.timestamp < vestCliff) {
    vestedUnits = 0
} else if (block.timestamp >= vestEnd) {
    vestedUnits = totalUnits
} else {
    vestedUnits = totalUnits * (block.timestamp - vestStart) / (vestEnd - vestStart)
}
```

2. Snapshot the vested amount: set `units` to `vestedUnits` at the time of revocation.
3. Record the revoked quantity: set `revoked_units` to `totalUnits - vestedUnits`.
4. Record the revocation timestamp: set `revoked_at` to `block.timestamp`.
5. Halt further vesting: the `vestedUnits()` function MUST return the snapshot value for revoked stakes. It MUST NOT continue vesting calculations after revocation.

When `revocation_mode` is `ANY`, the full stake (vested and unvested) is revoked. The implementation MUST set `revoked_units` to `units`, set `units` to 0, and record `revoked_at`.

### 9.3 Evidence Safety

Even when a certificate is voided or revoked, the chain retains its history and its link to the Pact version. The `revoked_units` and `revoked_at` fields provide a complete audit trail.

## 10. Mass Distribution

Mass distribution uses an Issuer-Signed Pact with an open counterparty.

The issuer publishes a Pact that defines terms for eligibility-based claiming.

### 10.1 Issuer-Mint Mode (Default)

Issuer verifies eligibility offchain and mints Claims to recipient addresses, paying gas.

### 10.2 Self-Claim Mode (Permitted)

For large distributions, the standard permits recipient-driven minting where recipients pay gas.

In self-claim mode, the issuer MUST commit an eligibility_rule_hash in the Pact (or in the Claim's conversionHash provenance). The issuer SHOULD publish an eligibility_root (for example a Merkle root) offchain or onchain. The application-defined proof system MUST deterministically map a recipient to an issuance record, and the resulting minted Claim MUST reference the Pact.

Self-claim mode exists to make 10k–100k recipient distributions feasible without forcing issuer-paid gas.

## 11. Standard Interfaces

### 11.1 IPactRegistry

A conforming implementation MUST support creation and lookup of Pact versions by pact_id.

```solidity
interface IPactRegistry {
    function createPact(...) external returns (bytes32 pactId);
    function amendPact(...) external returns (bytes32 newPactId);
    function getPact(bytes32 pactId) external view returns (Pact memory);
    function pactExists(bytes32 pactId) external view returns (bool);
    function computePactId(bytes32 issuerId, bytes32 contentHash, string calldata pactVersion) external pure returns (bytes32);
}
```

### 11.2 IClaimCertificate

A conforming implementation MUST support issuer minting of non-transferable ERC-721 Claims.

```solidity
interface IClaimCertificate {
    function issueClaim(address to, bytes32 pactId, uint256 maxUnits, uint8 unitType, uint64 redeemableAt) external returns (uint256 claimId);
    function voidClaim(uint256 claimId, bytes32 reasonHash) external;
    function markRedeemed(uint256 claimId, bytes32 reasonHash) external;
    function getClaim(uint256 claimId) external view returns (ClaimState memory);
}
```

### 11.3 IStakeCertificate

A conforming implementation MUST support conversion of a Claim into a Stake and MUST burn, void, or mark redeemed (terminal) the Claim in the same transaction.

```solidity
interface IStakeCertificate {
    function mintStake(address to, bytes32 pactId, uint256 units, uint8 unitType, uint64 vestStart, uint64 vestCliff, uint64 vestEnd, bool revocableUnvested) external returns (uint256 stakeId);
    function revokeStake(uint256 stakeId, bytes32 reasonHash) external;
    function getStake(uint256 stakeId) external view returns (StakeState memory);
    function vestedUnits(uint256 stakeId) external view returns (uint256);
    function unvestedUnits(uint256 stakeId) external view returns (uint256);
}
```

### 11.4 IStakeVault

A conforming implementation of the Vault MUST support the following operations:

```solidity
interface IStakeVault {
    function initializeFromTransition(uint256[] calldata certificateIds) external;
    function claimTokens(uint256 certificateId) external;
    function bidForSeat(uint256 certificateId, uint256 tokenAmount) external;
    function reclaimSeat(uint256 certificateId) external;
    function initiateOverride() external;
    function voteOverride(bool support) external;
    function executeOverride() external;

    function getGovernor(uint256 certificateId) external view returns (address governor, uint64 termStart, uint64 termEnd, uint256 bidAmount);
    function isGovernanceSeat(uint256 certificateId) external view returns (bool);
    function tokenAddress() external view returns (address);
}
```

### 11.5 IStakeToken

A conforming implementation of the post-transition token MUST implement ERC-20 with the following extensions:

```solidity
interface IStakeToken {
    function mint(address to, uint256 amount) external;
    function authorizedSupply() external view returns (uint256);
    function setAuthorizedSupply(uint256 newCap) external;
    function isLocked(address account) external view returns (bool);
    function lockUntil(address account) external view returns (uint64);
}
```

### 11.6 ERC-165 Interface IDs

Conforming implementations MUST support the following interface IDs:

| Interface          | ID           |
| ------------------ | ------------ |
| IERC5192           | 0xb45a3c0e   |
| IPactRegistry      | TBD          |
| IClaimCertificate  | TBD          |
| IStakeCertificate  | TBD          |
| IStakeVault        | TBD          |
| IStakeToken        | TBD          |

## 12. Transition

Transition is the irreversible event that converts a certificate-based private structure into a token-based public one.

### 12.1 Transition Trigger

Transition MUST be explicitly initiated by the issuer. Before initiation, the issuer SHOULD obtain governance approval from existing certificate holders (configurable threshold, RECOMMENDED: supermajority by unit-weighted vote).

The issuer calls `initiateTransition(address vault, address token, TransitionConfig config)`, providing the pre-deployed Vault and Token contract addresses and the transition configuration.

### 12.2 Transition Process

The transition executes as an atomic batch operation:

```
For each certificate (claim or stake) in the system:
  1. Unlock soulbound status                          (~5,000 gas)
  2. Transfer certificate to Vault                    (~50,000 gas)
  3. Mint ERC-20 tokens = vestedUnits of certificate  (~50,000 gas)
  4. Record lockup expiry for the holder              (~25,000 gas)
  5. Set TRANSITIONED status flag on certificate      (~5,000 gas)
```

Total gas per certificate: approximately 130,000. A 50-person cap table transitions in a single transaction for approximately 6.5 million gas, well within Ethereum's 30 million gas block limit.

For cap tables exceeding approximately 200 holders, the transition MUST support batched execution across multiple transactions. The `transitioned` flag MUST be set on the first batch call and all subsequent batches MUST check this flag.

Unvested units at the time of transition are NOT lost. The Vault MUST track the original vesting schedule and release tokens as they vest according to the original terms.

### 12.3 Transition Configuration

The `TransitionConfig` struct defines per-project parameters:

| Field                   | Type    | Default        | Meaning                                                |
| ----------------------- | ------- | -------------- | ------------------------------------------------------ |
| lockup_duration         | uint64  | 90 days        | Insider token lockup period after transition            |
| authorized_supply       | uint256 | (required)     | Hard cap on total token supply                         |
| public_offering_bps     | uint16  | 1500 (15%)     | Percentage of authorized supply for public offering    |
| liquidity_bps           | uint16  | 400 (4%)       | Percentage of authorized supply for liquidity pool     |
| contributor_pool_bps    | uint16  | 1200 (12%)     | Percentage for future contributor compensation         |
| community_bps           | uint16  | 300 (3%)       | Percentage for community/retroactive rewards           |
| governance_term_days    | uint32  | 365            | Default governance seat term in days                   |
| auction_min_bid_bps     | uint16  | 1000 (10%)     | Minimum bid for governance seat as % of cert units     |
| override_threshold_bps  | uint16  | 5001 (50%+1)   | Token holder override threshold in basis points        |
| override_quorum_bps     | uint16  | 2000 (20%)     | Token holder override quorum in basis points           |

All basis point parameters use a base of 10,000 (100% = 10000).

### 12.4 Issuer Power Freeze

After transition, the following operations MUST revert:

| Function | Rationale |
| --- | --- |
| `createPact` | No new agreements post-transition; governance controls issuance |
| `amendPact` | Terms are frozen at transition |
| `issueClaim` | New issuance governed by token supply controls (§16) |
| `voidClaim` | No unilateral voiding of existing instruments |
| `revokeStake` | No unilateral revocation; vesting continues per original terms |

The Vault and governance system replace issuer authority for all post-transition operations.

### 12.5 Price Discovery

The public offering tranche (default 15-20% of authorized supply) SHOULD be distributed via a Dutch auction:

1. The auction starts at a price above the expected market clearing price.
2. The price decreases over a defined period (RECOMMENDED: 3-7 days).
3. Participants place bids specifying quantity and maximum price.
4. When the auction concludes, all winning bidders pay the same clearing price — the lowest price at which all offered tokens are sold.

The auction produces a single, market-determined price. No underwriter sets the price. The auction contract MAY be deployed separately or integrated into the Vault.

### 12.6 Initial Liquidity

The liquidity allocation (default 3-5% of authorized supply) is paired with collateral from the auction proceeds to seed a permanent liquidity pool on a decentralized exchange.

This is protocol-owned liquidity. It SHOULD NOT be withdrawable by governance except by supermajority vote. The protocol earns trading fees from the position.

## 13. The Vault

The Vault is the central post-transition contract. It receives certificates at transition, mints tokens, manages governance seats, and administers auctions.

### 13.1 Vault Deployment

The Vault contract MUST be deployed before `initiateTransition()` is called. The StakeCertificates contract MUST verify the Vault implements the `IStakeVault` interface before proceeding with transition.

The Vault is initialized with:
- The address of the StakeCertificates contract (to verify incoming certificates)
- The address of the StakeToken contract (to mint tokens)
- The TransitionConfig parameters

### 13.2 Certificate Custody

After transition, the Vault holds all certificates that are not currently assigned to active governors. Certificates in the Vault are in a "pool" state — available for governance seat auction.

The Vault MUST track, for each certificate:
- Original holder address (for token distribution)
- Vested and unvested units at transition time
- Ongoing vesting schedule (if applicable)
- Whether the certificate is currently assigned to a governor

### 13.3 Token Minting and Distribution

At transition, the Vault mints tokens for each certificate:

- **Vested units**: Tokens are minted and held in escrow, claimable after the lockup period.
- **Unvested units**: Tokens are minted as they vest, following the original vesting schedule. The Vault tracks `vestStart`, `vestCliff`, and `vestEnd` from the original StakeState and releases tokens on a continuous or periodic basis.

Token claiming is pull-based: holders call `claimTokens(certificateId)` to withdraw their available (vested, unlocked) tokens.

### 13.4 Lockup Enforcement

During the lockup period (default 90 days), insider tokens MUST NOT be transferable on the open market. However, locked tokens MAY be used for:

- **Governance seat bids**: Depositing tokens to bid on governance seats does not create market sell pressure.
- **Token holder votes**: Locked tokens count toward quorum and vote totals for override votes.

The lockup is enforced at the token contract level via transfer restrictions that check the `lockUntil` timestamp per account. The Vault and governance contracts are whitelisted recipients during lockup.

### 13.5 Governance Seat Management

The Vault administers the governance seat lifecycle:

1. **Seat availability**: After transition, all certificates in the Vault are available seats. Seats are assigned staggered initial term expiry dates to ensure governance continuity.
2. **Auction**: When a seat becomes available, the Vault opens a bidding period. Any token holder may bid. See §15.3.
3. **Award**: The winning bidder's tokens are deposited, and the certificate is transferred to their wallet (re-locked for the term duration).
4. **Reclaim**: At term end, anyone MAY call `reclaimSeat(certificateId)`. The Vault forces the certificate back from the governor's wallet and opens a new auction.

## 14. Token Standard

The post-transition token is a standard ERC-20 with extensions for authorized supply management and lockup enforcement.

### 14.1 ERC-20 Base

The token MUST implement the full ERC-20 interface (transfer, approve, transferFrom, balanceOf, totalSupply, allowance). It MUST be compatible with existing DeFi infrastructure (DEXs, lending protocols, governance frameworks).

### 14.2 Authorized Supply

The token contract MUST enforce a hard cap (`authorizedSupply`) on the maximum number of tokens that can ever be minted. `totalSupply` MUST NOT exceed `authorizedSupply` at any time.

The `authorizedSupply` is set at transition and MAY only be increased by a token holder supermajority vote (RECOMMENDED: 66%+ of votes cast, 25% quorum of total supply). This is the equivalent of a corporate charter amendment.

### 14.3 Issuance Controls

Post-transition token minting is governed by the following rules:

| Annual Issuance                  | Required Approval                                        |
| -------------------------------- | -------------------------------------------------------- |
| Up to 20% of outstanding supply | Governance approval (certificate holder vote in the Vault) |
| Beyond 20% of outstanding supply | Token holder vote (50%+1, 20% quorum)                   |
| Beyond authorized supply         | Not possible without increasing authorized supply        |

The 20% threshold resets annually from the date of transition. Governance MUST track cumulative issuance within each annual period.

### 14.4 Lockup Mechanics

The token contract MUST support per-address lockup timestamps:

```solidity
mapping(address => uint64) public lockUntil;
```

Transfers from a locked address MUST revert, except when the recipient is:
- The Vault contract (governance seat bids)
- A governance voting contract (override votes)

After the lockup timestamp passes, the address is fully unlocked and tokens are freely transferable.

## 15. Post-Transition Governance

Post-transition governance replaces issuer control with a system based on two instruments: certificates (governance seats) and tokens (economic voting).

### 15.1 Governance Seats

Each certificate in the Vault represents one governance seat. The governance weight of a seat equals the unit count on the certificate. A certificate with 10,000 units carries more governance weight than one with 1,000 units.

Governance seats decide:
- Token issuance within the 20% annual limit
- Vault parameter changes
- Protocol operational decisions
- Market maker authorizations and liquidity management

### 15.2 Term Limits

Every governance seat has a fixed term (configurable, default 1 year). At the end of a term, the seat returns to the Vault and goes up for re-auction. No governor holds a seat indefinitely.

At transition, seats MUST be assigned staggered initial term expiry dates. For `N` seats with term length `T`, the `i`-th seat expires at `transitionTimestamp + (T * (i + 1)) / N`. This ensures governance continuity — the entire governance body never turns over simultaneously.

### 15.3 Seat Auction

When a governance seat becomes available (initial stagger expiry, term end, or override), the Vault opens a bidding period:

1. **Bidding period**: A fixed window (RECOMMENDED: 7 days) during which any token holder may submit a bid.
2. **Bid denomination**: Bids are denominated in tokens. The bidder deposits tokens into the Vault as their bid.
3. **Minimum bid**: The bid MUST meet or exceed the auction floor, calculated as `(certificate.units * auction_min_bid_bps) / 10000` tokens. Default floor: 10% of the certificate's unit count.
4. **Winner selection**: Highest bid wins. In case of a tie, the first bidder wins.
5. **Losing bids**: Returned to bidders immediately after the auction closes.
6. **Winning bid**: Tokens remain deposited in the Vault for the duration of the term. At term end, the tokens are returned to the governor (they paid "rent" for governance by locking capital, not by forfeiting it).

### 15.4 Certificate Custody During Governance

When a governor wins a seat:
1. The certificate is transferred from the Vault to the governor's wallet.
2. The certificate is re-locked (soulbound) for the term duration.
3. The governor holds the certificate visibly — it is compatible with DAO tooling, wallet UIs, and identity systems that read ERC-721 ownership.
4. The governor MUST NOT be able to transfer the certificate during the term.

### 15.5 Forced Reclaim

At term end, the seat MUST be reclaimed. The `reclaimSeat(uint256 certificateId)` function:

1. MUST be callable by anyone (permissionless) once `block.timestamp >= termEnd`.
2. Executes a forced transfer of the certificate from the governor's wallet back to the Vault.
3. Returns the governor's bid tokens.
4. Opens a new auction for the seat.

The forced transfer is possible because the certificate contract allows the Vault contract address to transfer tokens regardless of soulbound status. This is enforced in the `_update` hook:

```
if (msg.sender == vault || msg.sender == address(this)) → allow transfer
else if (from != address(0) && to != address(0)) → revert Soulbound()
```

### 15.6 Governance Simplification

Post-transition, the complex pre-transition governance structures (Power, Priority, seniority tiers, class votes) are replaced with two simple rules:

- **Governance weight** = certificate unit count (for governors holding seats)
- **Voting power** = token balance (for token holder votes)

No tiers, no seniority classes, no priority waterfall. This is the governance simplification event.

### 15.7 Token Holder Override

Token holders have one emergency power: replace all governors. This is the nuclear option.

| Parameter | Value |
| --- | --- |
| Trigger | Any token holder proposes an override |
| Voting period | 14 days (RECOMMENDED) |
| Threshold | 50%+1 of votes cast |
| Quorum | 20% of total token supply |
| Effect | All governors removed, all seats return to Vault, emergency auctions for all seats |
| Cooldown | 90 days before another override can be proposed |

Locked tokens (during the lockup period) MAY vote in override proposals. Override is the only mechanism through which token holders can directly affect governance. All other governance decisions require holding a seat.

## 16. Supply Architecture and Anti-Dilution

### 16.1 Authorized / Issued / Reserved Model

The token supply follows the authorized/issued/outstanding model used in traditional corporate governance:

- **Authorized supply**: The hard cap. Set at transition. Increase requires supermajority.
- **Issued supply**: Tokens that have been minted and are in circulation or in escrow.
- **Reserved supply**: The difference between authorized and issued. Available for future issuance under governance control.

### 16.2 Default Allocation

The following allocation represents the RECOMMENDED defaults. Each project MAY customize within the authorized supply:

| Allocation | Default % | Notes |
| --- | --- | --- |
| Existing stakeholders | 55-65% | 1:1 from certificates. Vesting carries over. Subject to lockup. |
| Public offering | 15-20% | New tokens via Dutch auction. This is the dilution event. |
| Liquidity provision | 3-5% | Paired with auction proceeds for permanent DEX pool. |
| Contributor pool | 10-15% | Future compensation. 4-year vest, 1-year cliff recommended. |
| Community | 2-5% | Retroactive rewards for genuine early users. Capped. |
| Unissued reserve | 0-10% | Authorized but not minted. Governance-controlled future issuance. |

### 16.3 Anti-Dilution Safeguards

The protocol provides five layers of protection against reckless dilution:

1. **The 20% rule**: Annual issuance beyond 20% of outstanding supply requires a token holder vote (§14.3).
2. **The authorized cap**: Total supply cannot exceed the authorized maximum. Increasing the cap requires a supermajority (§14.2).
3. **Onchain transparency**: Every issuance event is recorded on Ethereum. There is no hidden dilution.
4. **The override**: Token holders who believe governance is diluting recklessly may invoke the emergency override (§15.7) to replace all governors.
5. **Optional preemptive rights**: Projects MAY enable the `PRO_PREEMPTIVE` clause (§5.4), giving existing token holders the first right to purchase new issuance proportional to their current holdings.

## 17. Acquisitions

### 17.1 Pre-Transition Acquisitions

When both acquirer and target are in the certificate phase, acquisition is necessarily friendly. Soulbound certificates cannot be purchased on an open market.

Process:
1. Acquirer and target agree on terms (price per unit, consideration type).
2. Target's issuer initiates a dissolution event, functionally equivalent to transition but without token minting.
3. All certificates are voided and consideration is distributed to holders based on their units.
4. Consideration MAY be: the acquirer's certificates (stock-for-stock), ETH/stablecoins (cash deal), or a combination.

For stock-for-stock deals, the acquirer's issuer mints new certificates for the target's holders. The target's holders become stakeholders in the acquiring entity.

### 17.2 Post-Transition Acquisitions

After transition, three acquisition paths exist:

**Friendly merger**: Both governance bodies vote to approve. Token holders of the target ratify. A smart contract executes the exchange: target tokens become redeemable for acquirer tokens or stablecoins at the agreed ratio. The target's Vault dissolves and governance certificates are voided.

**Tender offer**: The acquirer offers to buy target tokens at a premium. If the acquirer accumulates more than 50% of the target's token supply, they may invoke the token holder override to replace all governors and gain control.

**Governance seat accumulation**: The acquirer bids on the target's governance seats over multiple term cycles, gradually gaining majority control.

## 18. Reference Implementation

This is a compact, auditable reference implementation intended as a readable baseline. Production deployments MUST be independently audited.

See [contracts/src/StakeCertificates.sol](../contracts/src/StakeCertificates.sol) for the pre-transition reference implementation.

The post-transition contracts (Vault, Token, Governance) are specified in §12-§15 and will be provided as separate reference implementations.

## 19. Canonical JSON Payloads (Normative Hashing)

Canonical encoding rule for any JSON hashed into content_hash, rights_root inputs, params_hash, vestingHash, conversionHash, revocationHash is RFC 8785 (JSON Canonicalization Scheme, JCS), UTF-8.

All hashes in this standard are `keccak256(JCS_bytes)`.

### 19.1 Pact JSON Example

```json
{
  "schema": "pact.v1",
  "issuer_id": "0x...",
  "pact_version": "1.0.0",
  "governing_law": "Delaware",
  "dispute_venue": "Delaware Chancery Court",
  "mutability": "mutable",
  "amendment": {"mode": "issuer_only", "scope": "future_only"},
  "revocation": {"mode": "unvested_only"},
  "signing_mode": "issuer_only",
  "rights": {
    "power": [{"clause_id": "PWR_VOTE", "enabled": true, "params": {"weight_bps": 10000, "class_vote_required": false}}],
    "priority": [],
    "protections": [
      {"clause_id": "PRO_LOCKUP", "enabled": true, "params": {"lockup_days": 90}},
      {"clause_id": "PRO_PREEMPTIVE", "enabled": false, "params": {"enabled": false, "based_on_fully_diluted": true}}
    ]
  },
  "custom_terms_uri": "ipfs://...",
  "custom_terms_hash": "0x..."
}
```

### 19.2 Conversion JSON Example

```json
{
  "schema": "conversion.v1",
  "mode": "IMMEDIATE",
  "conditions": [],
  "issuer_confirm_required": true
}
```

Conversion modes:

| Mode        | Meaning                                              |
| ----------- | ---------------------------------------------------- |
| IMMEDIATE   | Redeemable immediately upon issuance                 |
| TIMED       | Redeemable after redeemableAt timestamp              |
| MILESTONE   | Redeemable upon milestone completion (offchain)      |
| FUNDING     | Redeemable upon funding confirmation (offchain)      |
| ELIGIBILITY | Redeemable upon eligibility verification             |

### 19.3 Vesting JSON Example

```json
{
  "schema": "vesting.v1",
  "schedule": "LINEAR",
  "start": 1730000000,
  "cliff": 1732600000,
  "end": 1762000000
}
```

Vesting schedules:

| Schedule  | Meaning                                              |
| --------- | ---------------------------------------------------- |
| NONE      | Fully vested immediately                             |
| LINEAR    | Linear vesting from start to end with cliff          |
| MONTHLY   | Monthly cliff vesting                                |
| CUSTOM    | Custom schedule defined by additional params         |

### 19.4 Transition Config JSON Example

```json
{
  "schema": "transition.v1",
  "authorized_supply": "100000000000000000000000000",
  "lockup_duration_days": 90,
  "public_offering_bps": 1500,
  "liquidity_bps": 400,
  "contributor_pool_bps": 1200,
  "community_bps": 300,
  "governance_term_days": 365,
  "auction_min_bid_bps": 1000,
  "override_threshold_bps": 5001,
  "override_quorum_bps": 2000,
  "auction_duration_days": 7,
  "override_voting_days": 14,
  "override_cooldown_days": 90
}
```

### 19.5 Governance Seat JSON Example

```json
{
  "schema": "governance_seat.v1",
  "certificate_id": 42,
  "governor": "0x...",
  "term_start": 1730000000,
  "term_end": 1761536000,
  "bid_amount": "5000000000000000000000",
  "unit_count": 10000,
  "governance_weight": 10000
}
```

## 20. Security and Operational Notes

### 20.1 Authority Separation

Issuer authority SHOULD be a multisig. The reference code uses a single issuer role for simplicity.

Conforming implementations SHOULD separate roles:
- `AUTHORITY_ROLE`: Pact creation, claim issuance, stake conversion
- `PAUSER_ROLE`: Emergency pause/unpause (see §20.5)
- `DEFAULT_ADMIN_ROLE`: Role administration

### 20.2 Idempotence

Conforming implementations MUST be idempotent for issuance and redemption. The reference implementation enforces idempotence via issuanceId and redemptionId mappings that prevent double-mints across retries.

### 20.3 Privacy

Do not store sensitive personal data onchain. Store hashes and URIs only.

### 20.4 Upgrade Path

The reference implementation is not upgradeable. Production deployments SHOULD consider:
- Proxy patterns for upgradeability
- Migration paths between contract versions

### 20.5 Emergency Pause

Conforming implementations MUST implement an emergency pause mechanism. When paused, all state-changing functions MUST revert. The pause MUST be controlled by a dedicated `PAUSER_ROLE`, separate from the `AUTHORITY_ROLE`.

RECOMMENDED: Implement OpenZeppelin's `Pausable` with `whenNotPaused` guards on all state-changing functions.

Post-transition, the pause authority transfers to governance (certificate holder vote to pause/unpause).

### 20.6 Governance Attack Vectors

Post-transition governance faces several attack vectors:

**Governance capture via auction**: An attacker bids on all governance seats. Mitigated by: minimum bid floors (10% of cert units), term limits (attack must be sustained across multiple cycles), and token holder override (captured governors can be replaced).

**Token holder override abuse**: A whale with >50% voting power force-replaces governors. Mitigated by: 20% quorum requirement (needs broad participation), 90-day cooldown between overrides, and the cost of acquiring >50% of supply.

**Flash loan governance attacks**: Borrowing tokens to vote. Mitigated by: governance seat bidding requires token deposit locked for a full term (not a flash-loan-compatible timeframe). Override votes SHOULD use a snapshot mechanism where voting power is determined at proposal creation, not at vote time.

**Transition front-running**: An attacker seeing the transition transaction in the mempool attempts to manipulate state. Mitigated by: transition is a privileged operation (issuer-only) and the batch operation is atomic.

## 21. Compliance Stance

This standard provides a verifiable certificate record and an optional transition mechanism. It does not claim to be a security issuance framework, and it does not embed any jurisdictional compliance logic.

Issuers are responsible for ensuring compliance with applicable securities laws, KYC/AML requirements, and other regulatory obligations in their jurisdiction.

Pre-transition, certificates are non-transferable and issuer-controlled — they function as cap table records, not tradeable instruments. Post-transition, tokens are freely transferable and may be subject to securities regulation depending on jurisdiction.

## 22. References

- [ERC-721: Non-Fungible Token Standard](https://eips.ethereum.org/EIPS/eip-721)
- [ERC-20: Token Standard](https://eips.ethereum.org/EIPS/eip-20)
- [ERC-5192: Minimal Soulbound NFTs](https://eips.ethereum.org/EIPS/eip-5192)
- [ERC-165: Standard Interface Detection](https://eips.ethereum.org/EIPS/eip-165)
- [RFC 8785: JSON Canonicalization Scheme (JCS)](https://datatracker.ietf.org/doc/html/rfc8785)
- [RFC 2119: Key Words for Use in RFCs](https://datatracker.ietf.org/doc/html/rfc2119)
- [NYSE Listed Company Manual, Section 312.03: Shareholder Approval Policy](https://nyseguide.srorules.com/listed-company-manual)
- [OpenZeppelin Contracts v5](https://docs.openzeppelin.com/contracts/5.x/)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
