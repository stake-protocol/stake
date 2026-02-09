# Stake Protocol — Soulbound Equity Certificates

Status: Draft v0.4

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

1. All outstanding stake certificates are transferred to the Vault via vault-initiated transfers (soulbound bypass) in batched operations.
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

Pact fields are split between onchain storage (the `Pact` struct) and offchain content (the canonical Pact JSON referenced by `content_hash` and `uri`). The onchain struct stores only what is needed for protocol enforcement. All legal, amendment, dispute, and signing terms are in the offchain Pact JSON document, verifiable via `content_hash`.

#### 5.2.1 Onchain Fields (Pact Struct)

| Field                     | Type           | Meaning                                                         |
| ------------------------- | -------------- | --------------------------------------------------------------- |
| pact_id                   | bytes32        | Deterministic ID (see §5.1)                                     |
| issuer_id                 | bytes32        | Issuer namespace                                                |
| authority                 | address        | Authority address at Pact creation time                         |
| content_hash              | bytes32        | Hash of canonical Pact JSON                                     |
| supersedes_pact_id        | bytes32        | Previous Pact version ID (bytes32(0) if original)               |
| rights_root               | bytes32        | Root hash of standardized rights schema payload                 |
| uri                       | string         | IPFS/Arweave/HTTPS pointer to the Pact content                  |
| pact_version              | string         | Semantic version identifier                                     |
| mutable_pact              | bool           | Whether this Pact allows amendments                             |
| revocation_mode           | uint8 (enum)   | 0 = NONE, 1 = UNVESTED_ONLY, 2 = ANY                           |
| default_revocable_unvested| bool           | Whether stakes under this Pact are revocable by default         |

#### 5.2.2 Offchain Fields (Pact JSON)

The following fields are stored in the canonical Pact JSON document and verified via `content_hash`. They are NOT stored onchain.

| Field               | Type    | Meaning                                                                                   |
| ------------------- | ------- | ----------------------------------------------------------------------------------------- |
| amendment_mode      | string  | "none", "issuer_only", "multisig_threshold", or "external_rules"                          |
| amendment_scope     | string  | "future_only" or "retroactive_allowed_if_flagged"                                         |
| dispute_law         | string  | Governing law                                                                             |
| dispute_venue       | string  | Venue                                                                                     |
| signing_mode        | string  | "issuer_only", "countersign_required_offchain", or "countersign_required_onchain"          |
| custom_terms_hash   | bytes32 | Hash of any custom text bundle referenced by the Pact                                     |
| custom_terms_uri    | string  | URI to custom terms document                                                              |

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

Certificates SHOULD expose tokenURI metadata for broad wallet/indexer compatibility. The tokenURI JSON SHOULD include issuer_id, pact_id, certificate type, unit_type, and units so a third party can identify the certificate without bespoke ABI calls. Detailed rights and terms are resolved via the referenced Pact's `content_hash` and `rights_root`.

### 6.1 Unit Type Enumeration

The `unit_type` field uses the following values:

| Value | Name   | Meaning                                    |
| ----- | ------ | ------------------------------------------ |
| 0     | SHARES | Whole share units                          |
| 1     | BPS    | Basis points (10000 = 100%)                |
| 2     | WEI    | Wei-denominated fractional units           |
| 3     | CUSTOM | Custom unit type defined in Pact           |

Conforming implementations MUST store the `unit_type` on each certificate (both Claims and Stakes), not only in the Pact. This ensures that the unit domain is unambiguously readable from the certificate itself without requiring a Pact lookup.

### 6.2 Certificate Status

Certificate status is tracked via individual boolean fields on each certificate struct, not a bitfield. This keeps the storage layout simple and avoids bitwise operations in the EVM.

**Claim status fields:**

| Field           | Type | Meaning                                    |
| --------------- | ---- | ------------------------------------------ |
| voided          | bool | Claim has been voided by issuer            |
| fullyRedeemed   | bool | All units have been redeemed to Stakes     |

A Claim with `redeemedUnits > 0` but `fullyRedeemed == false` is partially redeemed — it can still be redeemed for remaining units.

**Stake status fields:**

| Field   | Type | Meaning                     |
| ------- | ---- | --------------------------- |
| revoked | bool | Stake has been revoked      |

### 6.3 Claim Fields

The onchain `ClaimState` struct stores the following fields. The `pact_id` is stored in a separate mapping (`claimPact`), and the owner is tracked by the ERC-721 `ownerOf`.

| Field           | Type    | Meaning                                                |
| --------------- | ------- | ------------------------------------------------------ |
| voided          | bool    | Whether the claim has been voided                      |
| fullyRedeemed   | bool    | Whether all units have been redeemed                   |
| issuedAt        | uint64  | Timestamp of issuance                                  |
| redeemableAt    | uint64  | Timestamp after which claim is redeemable (0 = immediate) |
| unitType        | uint8   | Units domain (see §6.1)                                |
| maxUnits        | uint256 | Upper bound units claimable                            |
| redeemedUnits   | uint256 | Units already redeemed to Stakes                       |
| reasonHash      | bytes32 | Hash of the most recent void/redemption reason         |

Conversion conditions (IMMEDIATE, TIMED, MILESTONE, FUNDING, ELIGIBILITY) are expressed via `redeemableAt` for time-based conditions and offchain verification for other modes. The conversion payload is stored in the offchain Pact JSON, verifiable via `content_hash`.

### 6.4 Stake Fields

The onchain `StakeState` struct stores the following fields. The `pact_id` is stored in a separate mapping (`stakePact`), and the owner is tracked by the ERC-721 `ownerOf`.

| Field              | Type    | Meaning                                                   |
| ------------------ | ------- | --------------------------------------------------------- |
| revoked            | bool    | Whether the stake has been revoked                        |
| issuedAt           | uint64  | Timestamp of issuance                                     |
| vestStart          | uint64  | Vesting start timestamp                                   |
| vestCliff          | uint64  | Vesting cliff timestamp (no vesting before this)          |
| vestEnd            | uint64  | Vesting end timestamp (fully vested at or after this)     |
| revokedAt          | uint64  | Timestamp of revocation (0 if none)                       |
| revocableUnvested  | bool    | Whether unvested portion is revocable                     |
| unitType           | uint8   | Units domain (see §6.1)                                   |
| units              | uint256 | Issued units (reduced to vested amount on revocation)     |
| revokedUnits       | uint256 | Units removed by revocation (0 if none)                   |
| reasonHash         | bytes32 | Hash of the revocation reason                             |

Vesting parameters are stored directly on the stake rather than as a hash of an offchain payload. This enables the contract to calculate `vestedUnits()` and `unvestedUnits()` onchain, which is required for correct revocation behavior and transition token minting.

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

Revocation and voiding are two distinct operations. **Voiding** cancels a Claim. **Revocation** cancels unvested or all portions of a Stake. The two are decoupled — voiding is always available to the issuer regardless of the Pact's revocation_mode setting.

### 9.1 Claim Voiding

Claims MAY be voided by the authority at any time, regardless of the Pact's `revocation_mode`. Pre-transition only — voiding MUST revert after transition.

Voiding is decoupled from revocation mode because voiding cancels a pre-conversion instrument (a Claim), while revocation mode governs post-conversion instruments (Stakes). An issuer MUST be able to void a Claim even under a Pact with `revocation_mode = NONE`.

### 9.2 Stake Revocation

Stakes MAY be revoked only as permitted by the Pact's `revocation_mode`. Pre-transition only — revocation MUST revert after transition.

The three revocation modes are:

| Value | Mode           | Behavior                                           |
| ----- | -------------- | -------------------------------------------------- |
| 0     | NONE           | Revocation disabled. `revokeStake()` MUST revert.  |
| 1     | UNVESTED_ONLY  | Only unvested portion can be revoked.              |
| 2     | ANY            | Full stake (vested and unvested) can be revoked.   |

When `revocation_mode` is `UNVESTED_ONLY`, revocation MUST only affect the unvested portion. Additionally, a stake with `revocableUnvested = false` MUST NOT be revocable even under UNVESTED_ONLY mode. The implementation MUST:

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

A conforming implementation MUST support creation, amendment, and lookup of Pact versions by pact_id.

```solidity
interface IPactRegistry {
    function createPact(bytes32 issuerId, address authority, bytes32 contentHash, bytes32 rightsRoot, string calldata uri, string calldata pactVersion, bool mutablePact, RevocationMode revocationMode, bool defaultRevocableUnvested) external returns (bytes32 pactId);
    function amendPact(bytes32 oldPactId, bytes32 newContentHash, bytes32 newRightsRoot, string calldata newUri, string calldata newPactVersion) external returns (bytes32 newPactId);
    function getPact(bytes32 pactId) external view returns (Pact memory);
    function tryGetPact(bytes32 pactId) external view returns (bool exists, Pact memory pact);
    function pactExists(bytes32 pactId) external view returns (bool);
    function computePactId(bytes32 issuerId, bytes32 contentHash, string calldata pactVersion) external pure returns (bytes32);
}
```

`tryGetPact` returns `(false, empty)` instead of reverting when the Pact does not exist. This is useful for composability — callers can check existence without try/catch.

### 11.2 IClaimCertificate

A conforming implementation MUST support issuer minting of non-transferable ERC-721 Claims with partial redemption tracking.

```solidity
interface IClaimCertificate {
    function issueClaim(address to, bytes32 pactId, uint256 maxUnits, UnitType unitType, uint64 redeemableAt) external returns (uint256 claimId);
    function voidClaim(uint256 claimId, bytes32 reasonHash) external;
    function recordRedemption(uint256 claimId, uint256 units, bytes32 reasonHash) external;
    function getClaim(uint256 claimId) external view returns (ClaimState memory);
    function remainingUnits(uint256 claimId) external view returns (uint256);
    function exists(uint256 claimId) external view returns (bool);
}
```

`recordRedemption` supports partial redemption — a Claim with 10,000 maxUnits can be redeemed in multiple tranches (e.g., 5,000 + 3,000 + 2,000). The `fullyRedeemed` flag is set automatically when `redeemedUnits == maxUnits`. `remainingUnits` returns `maxUnits - redeemedUnits`.

### 11.3 IStakeCertificate

A conforming implementation MUST support conversion of a Claim into a Stake. When a partial redemption consumes all remaining units, the Claim is marked `fullyRedeemed`.

```solidity
interface IStakeCertificate {
    function mintStake(address to, bytes32 pactId, uint256 units, UnitType unitType, uint64 vestStart, uint64 vestCliff, uint64 vestEnd, bool revocableUnvested) external returns (uint256 stakeId);
    function revokeStake(uint256 stakeId, bytes32 reasonHash) external;
    function getStake(uint256 stakeId) external view returns (StakeState memory);
    function vestedUnits(uint256 stakeId) external view returns (uint256);
    function unvestedUnits(uint256 stakeId) external view returns (uint256);
    function exists(uint256 stakeId) external view returns (bool);
}
```

### 11.4 IStakeCertificates (Coordinator)

The coordinator contract is the main entry point. It orchestrates the registry, claims, and stakes and provides idempotence guarantees.

```solidity
interface IStakeCertificates {
    function createPact(bytes32 contentHash, bytes32 rightsRoot, string calldata uri, string calldata pactVersion, bool mutablePact, RevocationMode revocationMode, bool defaultRevocableUnvested) external returns (bytes32);
    function amendPact(bytes32 oldPactId, bytes32 newContentHash, bytes32 newRightsRoot, string calldata newUri, string calldata newPactVersion) external returns (bytes32);
    function issueClaim(bytes32 issuanceId, address to, bytes32 pactId, uint256 maxUnits, UnitType unitType, uint64 redeemableAt) external returns (uint256);
    function issueClaimBatch(bytes32[] calldata issuanceIds, address[] calldata recipients, bytes32 pactId, uint256[] calldata maxUnitsArr, UnitType unitType, uint64 redeemableAt) external returns (uint256[] memory);
    function voidClaim(bytes32 issuanceId, bytes32 reasonHash) external;
    function redeemToStake(bytes32 redemptionId, uint256 claimId, uint256 units, UnitType unitType, uint64 vestStart, uint64 vestCliff, uint64 vestEnd, bytes32 reasonHash) external returns (uint256);
    function revokeStake(uint256 stakeId, bytes32 reasonHash) external;
    function initiateTransition(address vault) external;
    function transferAuthority(address newAuthority) external;
    function setClaimBaseURI(string calldata newBaseURI) external;
    function setStakeBaseURI(string calldata newBaseURI) external;
}
```

`issueClaimBatch` provides gas-efficient batch issuance on L1 — issuing N claims in one transaction instead of N separate calls. All arrays MUST be the same length.

`transferAuthority` transfers all roles (AUTHORITY, PAUSER, DEFAULT_ADMIN) from the current authority to the new address. Pre-transition only.

### 11.5 IStakeVault

A conforming implementation of the Vault MUST support the following operations:

```solidity
interface IStakeVault {
    function processTransitionBatch(uint256[] calldata stakeIds, address liquidationRouter) external;
    function claimTokens() external;
    function releaseVestedTokens(uint256 stakeId) external;
    function startSeatAuction(uint256 certId) external;
    function bidForSeat(uint256 certId, uint256 amount) external;
    function settleAuction(uint256 certId) external;
    function reclaimSeat(uint256 certId) external;
    function proposeOverride() external returns (uint256 proposalId);
    function voteOverride(uint256 proposalId, bool support) external;
    function executeOverride(uint256 proposalId) external;

    function getGovernor(uint256 certId) external view returns (address governor, uint64 termStart, uint64 termEnd, uint256 bidAmount);
    function isGovernanceSeat(uint256 certId) external view returns (bool);
    function depositedStakeCount() external view returns (uint256);
}
```

### 11.6 IStakeToken

A conforming implementation of the post-transition token MUST implement ERC-20 with the following extensions:

```solidity
interface IStakeToken {
    function mint(address to, uint256 amount) external;
    function authorizedSupply() external view returns (uint256);
    function setAuthorizedSupply(uint256 newSupply) external;
    function setLockup(address account, uint64 until) external;
    function setLockupWhitelist(address target, bool whitelisted) external;
    function isLocked(address account) external view returns (bool);
    function lockUntil(address account) external view returns (uint64);
    function governanceBalance(address account) external view returns (uint256);
}
```

`governanceBalance` returns 0 for governance-excluded addresses (protocol fee address). This is used by the governance system to determine voting weight. See §18.2.

### 11.7 IProtocolFeeLiquidator

See §18.3 for the liquidator interface specification.

### 11.8 ERC-165 Interface IDs

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

Transition MUST be explicitly initiated by the authority. Before initiation, the authority SHOULD obtain governance approval from existing certificate holders (configurable threshold, RECOMMENDED: supermajority by unit-weighted vote).

The transition is a two-step process:

1. **Pre-deploy**: The Vault and Token contracts are deployed independently with their configuration parameters.
2. **Initiate**: The authority calls `initiateTransition(address vault)` on the StakeCertificates contract. This sets the vault address on the Claim and Stake child contracts (enabling vault-initiated transfers) and sets the `transitioned` flag.
3. **Process**: The Vault operator calls `processTransitionBatch(stakeIds, liquidationRouter)` to transfer certificates to the vault and mint tokens. This can be batched across multiple transactions for large cap tables.

### 12.2 Transition Process

The `processTransitionBatch` function processes stakes in batches:

```
For each stake in the batch:
  1. Transfer certificate from holder to Vault       (~50,000 gas)
  2. Record deposit metadata (holder, vesting schedule) (~25,000 gas)
  3. Mint ERC-20 tokens = vestedUnits at transition  (~50,000 gas)
  4. Set lockup expiry for the holder                (~25,000 gas)
```

The transfer is vault-initiated — the vault calls `transferFrom` on the stake contract, which is authorized in the `_update` hook regardless of soulbound status.

Total gas per stake: approximately 150,000. A 50-person cap table transitions in a single transaction for approximately 7.5 million gas, well within Ethereum's 30 million gas block limit.

The `transitioned` flag on StakeCertificates is set by `initiateTransition()` (step 1). The `transitionProcessed` flag on the Vault is set on the first `processTransitionBatch()` call. Subsequent batch calls process additional stakes.

Unvested units at the time of transition are NOT lost. The Vault MUST track the original vesting schedule. Anyone can call `releaseVestedTokens(stakeId)` to mint and allocate newly vested tokens to the original holder as they vest.

### 12.3 Transition Configuration

Transition parameters are set at deployment time on the Vault and Token contracts, not passed as a struct to `initiateTransition()`. This allows the vault and token to be independently deployed, verified, and audited before transition.

**Vault constructor parameters:**

| Parameter               | Type    | Default        | Meaning                                                |
| ----------------------- | ------- | -------------- | ------------------------------------------------------ |
| lockupDuration          | uint64  | 90 days        | Insider token lockup period after transition            |
| governanceTermDays      | uint32  | 365            | Default governance seat term in days                   |
| auctionMinBidBps        | uint16  | 1000 (10%)     | Minimum bid for governance seat as % of cert units     |
| overrideThresholdBps    | uint16  | 5001 (50%+1)   | Token holder override threshold in basis points        |
| overrideQuorumBps       | uint16  | 2000 (20%)     | Token holder override quorum in basis points           |

**Token constructor parameters:**

| Parameter               | Type    | Default        | Meaning                                                |
| ----------------------- | ------- | -------------- | ------------------------------------------------------ |
| authorizedSupply        | uint256 | (required)     | Hard cap on total token supply                         |

**Allocation parameters** (public offering, liquidity, contributor pool, community) are offchain planning decisions, not encoded in the contracts. The contracts enforce the authorized supply cap and issuance controls (§14.3) but do not prescribe how the reserved supply is allocated. See §16.2 for recommended defaults.

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

The Vault contract MUST be deployed before `initiateTransition()` is called. The Vault is initialized with:
- The address of the StakeCertificates contract (resolves to its STAKE child for transfers)
- The address of the StakeToken contract (for minting tokens)
- The protocol fee address (for fee token distribution)
- An operator address (for processing transition batches)
- Configuration parameters: lockup duration, governance term, auction/override thresholds

### 13.2 Certificate Custody

After transition, the Vault holds all certificates that are not currently assigned to active governors. Certificates in the Vault are in a "pool" state — available for governance seat auction.

The Vault MUST track, for each certificate:
- Original holder address (for token distribution)
- Vested and unvested units at transition time
- Ongoing vesting schedule (if applicable)
- Whether the certificate is currently assigned to a governor

### 13.3 Token Minting and Distribution

At transition, the Vault mints tokens for each stake certificate:

- **Vested units**: Tokens are minted during `processTransitionBatch()` and held in the Vault, claimable after the lockup period.
- **Unvested units**: Tokens are minted as they vest. Anyone can call `releaseVestedTokens(stakeId)` to calculate newly vested units and mint tokens allocated to the original holder. The Vault tracks `vestStart`, `vestCliff`, and `vestEnd` from the original StakeState.

Token claiming is pull-based: holders call `claimTokens()` to withdraw their available (vested, unlocked) tokens. The function checks the caller's lockup expiry and transfers all unclaimed tokens.

### 13.4 Lockup Enforcement

During the lockup period (default 90 days), insider tokens MUST NOT be transferable on the open market. However, locked tokens MAY be used for:

- **Governance seat bids**: Depositing tokens to bid on governance seats does not create market sell pressure.
- **Token holder votes**: Locked tokens count toward quorum and vote totals for override votes.

The lockup is enforced at the token contract level via transfer restrictions that check the `lockUntil` timestamp per account. The Vault and governance contracts are whitelisted recipients during lockup.

### 13.5 Governance Seat Management

The Vault administers the governance seat lifecycle through explicit steps:

1. **Start auction**: Anyone calls `startSeatAuction(certId)` for a certificate held by the Vault that is not currently governed. Opens a bidding period (default: 7 days).
2. **Bid**: Token holders call `bidForSeat(certId, amount)` during the bidding period. Tokens are deposited via `transferFrom`. If a higher bid arrives, the previous bidder's tokens are returned. See §15.3.
3. **Settle**: After the bidding period ends, anyone calls `settleAuction(certId)`. The winning bidder receives the certificate (vault-initiated transfer, bypasses soulbound), and the governance seat is activated for one term.
4. **Reclaim**: At term end, anyone calls `reclaimSeat(certId)`. The Vault forces the certificate back from the governor's wallet, returns their bid tokens, and marks the seat inactive.

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

Transfers from a locked address MUST revert, except when the recipient is in the lockup whitelist. The whitelist is initialized at deployment with the Vault and governance contract addresses, and MAY be updated by governance.

```solidity
mapping(address => bool) public lockupWhitelist;
```

This allows locked tokens to be used for governance seat bids (deposited to Vault) and override votes (deposited to governance) without creating market sell pressure.

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

When a governance seat becomes available, anyone calls `startSeatAuction(certId)` to open a bidding period:

1. **Bidding period**: A fixed window (default: 7 days) during which any token holder may submit a bid via `bidForSeat(certId, amount)`.
2. **Bid denomination**: Bids are denominated in tokens. The bidder's tokens are transferred to the Vault via `transferFrom` (requires prior approval).
3. **Minimum bid**: The bid MUST meet or exceed the auction floor, calculated as `(certificate.units * auctionMinBidBps) / 10000` tokens. Default floor: 10% of the certificate's unit count.
4. **Outbid handling**: When a higher bid arrives, the previous highest bidder's tokens are returned immediately. Only the current highest bid is held by the Vault at any time.
5. **Settlement**: After the bidding period ends, anyone calls `settleAuction(certId)`. If there were no bids, the seat stays in the Vault. Otherwise, the winner receives the certificate.
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

The forced transfer is possible because the certificate contract allows the Vault contract address to transfer tokens regardless of soulbound status. This is enforced in the `_update` hook via the `auth` parameter (set from `msg.sender` by `transferFrom`):

```
if (from != address(0) && to != address(0)):  // Transfer (not mint/burn)
    requireNotPaused()
    if (auth != vault) → revert Soulbound()
    allow transfer (skip standard auth check)
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
| Trigger | Any token holder calls `proposeOverride()` (must have non-zero `governanceBalance`) |
| Voting period | 14 days |
| Threshold | 50%+1 of votes cast |
| Quorum | 20% of total token supply |
| Effect | All governors removed, all seats return to Vault, bid tokens returned |
| Cooldown | 90 days before another override can be proposed |

The override flow is: `proposeOverride()` → `voteOverride(proposalId, support)` → `executeOverride(proposalId)`. Each proposal has a unique ID. Voting weight is determined by `governanceBalance` (excludes protocol fee address). Voters can only vote once per proposal.

Locked tokens (during the lockup period) MAY vote in override proposals via `governanceBalance` (which reads `balanceOf`, not transferable balance). Override is the only mechanism through which token holders can directly affect governance. All other governance decisions require holding a seat.

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

## 18. Protocol Fee

### 18.1 Fee Structure

The protocol charges an immutable 1% fee on tokens minted during transition. This fee is encoded in the Vault contract and cannot be modified, waived, or disabled.

When the Vault processes the transition batch, it MUST:
1. Calculate the total tokens minted for certificate holders in that batch.
2. Mint an additional 1% of that amount (100 basis points, base 10,000).
3. Transfer the fee tokens to the `ProtocolFeeLiquidator` contract.

The fee is denominated in the project's own tokens, not ETH or stablecoins.

### 18.2 Governance Exclusion

Protocol fee tokens MUST NOT carry governance rights. The `StakeToken` contract MUST expose a `governanceBalance(address)` function that returns 0 for governance-excluded addresses. The protocol fee address MUST be permanently excluded from governance voting and governance seat bidding.

This is a structural property encoded in the token contract, not a policy decision. It ensures the protocol cannot accumulate governance power across projects.

### 18.3 Protocol Fee Liquidator

The `ProtocolFeeLiquidator` is an autonomous, immutable contract deployed per-project during transition. It receives the 1% fee tokens and liquidates them on a fixed schedule.

**Properties:**
- **Immutable**: No admin functions, no pause, no override, no upgradability. Once deployed, it runs to completion.
- **Permissionless**: Anyone can call `liquidate()` — MEV bots, keepers, the protocol team, any address. The outcome is deterministic regardless of caller.
- **Predictable**: Anyone can calculate exactly how many tokens will be sold on any given day.
- **Transparent**: Every sale is an on-chain swap through a known router.

**Schedule:**
| Phase | Duration | Behavior |
| --- | --- | --- |
| Lockup | 90 days from transition | No tokens released. Same lockup as all insiders. |
| Linear vesting | 12 months after lockup | Tokens unlock linearly, available for liquidation. |
| Total | 15 months | All fee tokens fully liquidated. |

The 90-day lockup matches the standard insider lockup period. The protocol follows the same rules as every other holder.

**Liquidation mechanics:**
1. `releasable()` returns the number of tokens currently unlocked but not yet sold.
2. `liquidate()` sells all releasable tokens through the pre-configured swap router.
3. Sale proceeds go directly to the protocol treasury address.
4. If the router fails (no liquidity, pool paused), tokens accumulate and can be sold later.

The swap router is set at deployment time — it is the AMM pool seeded by the transition's initial liquidity (see §12.6). The router address is immutable after deployment.

**Liquidator interface:**
```solidity
interface IProtocolFeeLiquidator {
    function releasable() external view returns (uint256);
    function liquidate() external returns (uint256 tokensSold, uint256 proceeds);
    function schedule() external view returns (
        uint256 totalTokens,
        uint256 totalReleased,
        uint256 releasable_,
        uint64 lockupEnd,
        uint64 vestingEnd,
        uint16 percentComplete
    );
    function initialize() external;
}
```

**Liquidation router interface:**
```solidity
interface ILiquidationRouter {
    function liquidate(address tokenIn, uint256 amountIn, address recipient) external returns (uint256 amountOut);
}
```

Implementations of `ILiquidationRouter` wrap a specific DEX (Uniswap V2/V3, etc.) and handle routing, slippage, and execution. The reference implementation provides the interface; production deployments implement the router for their chosen DEX.

### 18.4 Rationale

The auto-sell is encoded rather than left to policy for the same reason soulbound status is encoded: if it matters, it must be trustless. A founder evaluating Stake Protocol should not need to trust the protocol team's liquidation promises. The schedule is verifiable, the mechanism is permissionless, and the outcome is guaranteed by code.

The 1% rate is set to remain below the fork-rationality threshold. Existing certificates reference the original contract addresses; forking the protocol at transition time does not migrate existing stakes. The cost of forking (independent audit, ecosystem integration, credibility) exceeds the 1% fee for any project below approximately $100M in token value.

## 19. Reference Implementation

This is a compact, auditable reference implementation intended as a readable baseline. Production deployments MUST be independently audited.

The reference implementation consists of:

| Contract | File | Purpose |
| --- | --- | --- |
| `StakeCertificates` | [contracts/src/StakeCertificates.sol](../contracts/src/StakeCertificates.sol) | Pre-transition coordinator, pact registry, claim and stake management |
| `StakeToken` | [contracts/src/StakeToken.sol](../contracts/src/StakeToken.sol) | ERC-20 with authorized supply, lockup, governance exclusion |
| `StakeVault` | [contracts/src/StakeVault.sol](../contracts/src/StakeVault.sol) | Post-transition vault, governance seats, auctions, transition processing |
| `ProtocolFeeLiquidator` | [contracts/src/ProtocolFeeLiquidator.sol](../contracts/src/ProtocolFeeLiquidator.sol) | Autonomous fee token liquidation |

## 20. Canonical JSON Payloads (Normative Hashing)

Canonical encoding rule for any JSON hashed into content_hash, rights_root, or params_hash is RFC 8785 (JSON Canonicalization Scheme, JCS), UTF-8.

All hashes in this standard are `keccak256(JCS_bytes)`.

### 20.1 Pact JSON Example

```json
{
  "schema": "pact.v1",
  "issuer_id": "0x...",
  "pact_version": "1.0.0",
  "governing_law": "Delaware",
  "dispute_venue": "Delaware Chancery Court",
  "amendment_mode": "issuer_only",
  "amendment_scope": "future_only",
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

This is the offchain Pact JSON document stored at the URI. Its `keccak256(JCS_bytes)` MUST equal the `content_hash` stored onchain. The onchain Pact struct stores only the fields needed for protocol enforcement (see §5.2.1). The legal terms (governing_law, dispute_venue, amendment rules, signing mode) are offchain-only and verified via `content_hash`.

### 20.2 Conversion JSON Example

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

### 20.3 Vesting JSON Example

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

### 20.4 Transition Config JSON Example

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

### 20.5 Governance Seat JSON Example

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

## 21. Security and Operational Notes

### 21.1 Authority and Role Separation

The authority address SHOULD be a multisig for production deployments. The reference implementation uses a single authority EOA that holds all roles.

The coordinator contract separates three roles:
- `AUTHORITY_ROLE`: Pact creation, claim issuance, stake conversion, transition
- `PAUSER_ROLE`: Emergency pause/unpause (see §21.5)
- `DEFAULT_ADMIN_ROLE`: Role administration

Authority is transferable via `transferAuthority(newAuthority)`. This transfers all three roles atomically to the new address and revokes them from the old address. Pre-transition only — authority powers freeze permanently at transition.

The child contracts (StakePactRegistry, SoulboundClaim, SoulboundStake) are administered exclusively by the StakeCertificates coordinator contract. No external EOA holds admin roles on child contracts. This ensures that authority rotation on the coordinator covers all protocol access without residual privilege on child contracts.

### 21.2 Idempotence

Conforming implementations MUST be idempotent for issuance and redemption. The reference implementation enforces idempotence via issuanceId and redemptionId mappings that prevent double-mints across retries.

### 21.3 Privacy

Do not store sensitive personal data onchain. Store hashes and URIs only.

### 21.4 Upgrade Path

The reference implementation is not upgradeable. Production deployments SHOULD consider:
- Proxy patterns for upgradeability
- Migration paths between contract versions

### 21.5 Emergency Pause

Conforming implementations MUST implement an emergency pause mechanism. When paused, all state-changing functions MUST revert. The pause MUST be controlled by a dedicated `PAUSER_ROLE`, separate from the `AUTHORITY_ROLE`.

RECOMMENDED: Implement OpenZeppelin's `Pausable` with `whenNotPaused` guards on all state-changing functions.

Post-transition, the pause authority transfers to governance (certificate holder vote to pause/unpause).

### 21.6 Governance Attack Vectors

Post-transition governance faces several attack vectors:

**Governance capture via auction**: An attacker bids on all governance seats. Mitigated by: minimum bid floors (10% of cert units), term limits (attack must be sustained across multiple cycles), and token holder override (captured governors can be replaced).

**Token holder override abuse**: A whale with >50% voting power force-replaces governors. Mitigated by: 20% quorum requirement (needs broad participation), 90-day cooldown between overrides, and the cost of acquiring >50% of supply.

**Flash loan governance attacks**: Borrowing tokens to vote. Mitigated by: governance seat bidding requires token deposit locked for a full term (not a flash-loan-compatible timeframe). Override votes SHOULD use a snapshot mechanism where voting power is determined at proposal creation, not at vote time.

**Transition front-running**: An attacker seeing the transition transaction in the mempool attempts to manipulate state. Mitigated by: transition is a privileged operation (issuer-only) and the batch operation is atomic.

## 22. Compliance Stance

This standard provides a verifiable certificate record and an optional transition mechanism. It does not claim to be a security issuance framework, and it does not embed any jurisdictional compliance logic.

Issuers are responsible for ensuring compliance with applicable securities laws, KYC/AML requirements, and other regulatory obligations in their jurisdiction.

Pre-transition, certificates are non-transferable and issuer-controlled — they function as cap table records, not tradeable instruments. Post-transition, tokens are freely transferable and may be subject to securities regulation depending on jurisdiction.

## 23. References

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
