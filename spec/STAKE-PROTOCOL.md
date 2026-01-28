# Stake Protocol — Soulbound Equity Certificates (SEC)

Status: Draft

## 1. Abstract

Stake Protocol defines a minimal onchain standard for issuing non-transferable equity certificates as verifiable, wallet-held records. The protocol models a deterministic lifecycle: Pact → Claim → Stake → Token (optional). A Pact is the canonical, versioned agreement that defines rights, issuer powers, amendment rules, revocation rules, and dispute terms. A Claim is a contingent certificate issued under a Pact. A Stake is the realized certificate after conversion from a Claim. Tokenization is optional and explicitly outside the core standard.

The standard is designed to minimize user actions, minimize divergence between cap table reality and chain state, and place operational burden on the issuer.

## 2. Terminology

**Issuer**: The issuing entity, corporation, company, DAO, BORG, project or protocol.

**Authority**: The onchain address set authorized to issue, amend, convert, revoke, or void under an Issuer. Default implementation uses a multisig.

**Pact**: **P**lain **A**greement for **C**ontract **T**erms. A versioned, content-addressed agreement that defines rights and lifecycle rules.

**Claim**: A non-transferable certificate representing a contingent right to receive a Stake under a Pact.

**Stake**: A non-transferable certificate representing an issued ownership position under a Pact.

**Void**: A terminal state marking a certificate as cancelled without erasing history.

**Revoke**: Cancellation of unvested or cancellable portions per Pact rules.

**Redeem**: Conversion of a Claim to a Stake certificate.

**Amend**: Creating a new Pact version, optionally binding future issuances and optionally affecting existing certificates only if the Pact explicitly allows it.

**Transition**: Optional initial public offering and token generation event where all stakes and claims convert to tokens.

## 3. Design Goals

The standard optimizes for three properties.

First, evidentiary clarity. The chain must carry a self-describing reference to the Pact version and rights bundle that defines "what the holder is supposed to have."

Second, minimal state and minimal user actions. The issuer confirms funding and the protocol mints immediately; recipients never need to pay gas to receive certificates.

Third, controlled flexibility. By default the issuer may revoke and amend within explicit Pact rules, while projects may opt into immutability by disabling those powers at the Pact level.

## 4. Core Lifecycle

The lifecycle is deterministic.

### 4.1 Pact Creation

An Issuer defines a Pact version. The Pact has a deterministic content hash and a stable pact_id. The Pact may be declared mutable or immutable, and may define amendment authority and amendment scope.

### 4.2 Claim Issuance

All certificate issuance starts as a Claim, even for immediate issuance.

Rationale: Claim is the universal issuance envelope. It unifies "pending conversion" instruments (SAFE-like, vesting-based, milestone-based, eligibility-based) with immediate issuance (redeemable immediately). The difference is only in conversion conditions.

### 4.3 Claim Conversion

A Claim converts to a Stake via Redeem. Default flow is issuer-driven and occurs once funds or conditions are confirmed. A Claim may be redeemable immediately.

### 4.4 Stake Vesting and Revocation

A Stake may include vesting metadata. Revocation and voiding are permitted only to the extent the referenced Pact grants them.

### 4.5 Optional Tokenization

An Issuer may later define a separate tokenization regime (Transition). Transition is explicitly out of scope for the core standard; the core standard only provides hooks and references.

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
| PRO_LOCKUP        | Protections | Transfer lockup in future tokenization   | until_ts                                              |

## 6. Certificate Model

Claims and Stakes are wallet-held ERC-721 tokens that are non-transferable.

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

### 6.2 Status Flags Bitfield

The `status_flags` field is a uint32 bitfield:

| Bit | Name     | Meaning                                    |
| --- | -------- | ------------------------------------------ |
| 0   | VOIDED   | Certificate has been voided                |
| 1   | REVOKED  | Stake has been revoked                     |
| 2   | REDEEMED | Claim has been converted to Stake          |
| 3   | DISPUTED | Certificate is under dispute               |
| 4-31| Reserved | Reserved for future use                    |

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

| Field         | Type    | Meaning                            |
| ------------- | ------- | ---------------------------------- |
| schema        | string  | stake.v1                           |
| issuer_id     | bytes32 | Issuer namespace                   |
| pact_id       | bytes32 | Pact version reference             |
| recipient     | address | Current owner address              |
| unit_type     | uint8   | Units domain (see 6.1)             |
| units         | uint256 | Issued units                       |
| vesting       | bytes32 | Hash of vesting payload            |
| revocation    | bytes32 | Hash of revocation payload         |
| status_flags  | uint32  | Bitfield (see 6.2)                 |
| issued_at     | uint64  | Timestamp                          |

### 6.5 Non-Transferability Signaling

Certificates MUST be non-transferable at the ERC-721 transfer layer.

Certificates MUST block approvals (approve and setApprovalForAll) to prevent UX-confusing "transfer-like" flows.

Certificates SHOULD implement ERC-5192 (Minimal Soulbound) and MUST advertise the ERC-5192 interface via ERC-165 supportsInterface.

## 7. Funding and Minting Rules

### 7.1 Default Issuance

Issuer confirms funds or satisfaction of conditions, then mints the Claim to the recipient address, paying gas. This avoids recipient gas failures and prevents "you own it but you haven't minted it yet" ambiguity.

### 7.2 Crypto Rail Optionality

The standard permits an atomic "pay and mint" pathway as an optional application feature, but it is not required by the standard and must converge to the same minted Claim state.

### 7.3 Cap Table Synchronization Rule

Only minted certificates count as issued onchain positions. Executed-but-unminted agreements remain offchain state.

If funds are received but minting fails, the issuer MUST retry until the certificate is minted or the agreement is formally cancelled per the Pact.

### 7.4 Idempotence Requirement

Conforming implementations MUST be idempotent for issuance and redemption. Each issuance and redemption MUST accept an external issuance_id / redemption_id (or deterministic key) and MUST prevent double-mints under retries.

## 8. Amendments and Immutability

Amendment is a new Pact version. A Pact declares whether amendments exist, who can create them, and whether amendments may apply retroactively.

Default is future-only: new issuances bind to the newest Pact version the issuer chooses; existing certificates remain bound to their pact_id.

Retroactive changes are allowed only if the old Pact explicitly allows them and the new Pact carries a retroactive flag. The onchain standard does not enforce legal validity; it enforces explicitness and auditability.

Immutability is a Pact-level choice. A Pact may set mutability to immutable, making amendments and revocations invalid for that Pact version.

## 9. Revocation and Voiding

Revocation is permitted only within Pact-defined modes. The standard includes the ability to mark certificates voided or revoked, and to record a reason hash.

### 9.1 Claim Voiding

Claims may be voided by the issuer if the Pact permits it.

### 9.2 Stake Revocation

Stakes may be revoked only as permitted by the Pact, typically unvested-only or per-stake flags.

When `revocation_mode` is `UNVESTED_ONLY`, revocation MUST only affect the unvested portion. The vested amount is calculated as:

```
if (block.timestamp < vestCliff) {
    vestedUnits = 0
} else if (block.timestamp >= vestEnd) {
    vestedUnits = totalUnits
} else {
    vestedUnits = totalUnits * (block.timestamp - vestStart) / (vestEnd - vestStart)
}
```

### 9.3 Evidence Safety

Even when a certificate is voided or revoked, the chain retains its history and its link to the Pact version.

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

### 11.1 PactRegistry Interface

A conforming implementation MUST support creation and lookup of Pact versions by pact_id.

### 11.2 ClaimCertificate Interface

A conforming implementation MUST support issuer minting of non-transferable ERC-721 Claims.

### 11.3 StakeCertificate Interface

A conforming implementation MUST support conversion of a Claim into a Stake and MUST burn, void, or mark redeemed (terminal) the Claim in the same transaction.

### 11.4 ERC-165 Interface IDs

Conforming implementations MUST support the following interface IDs:

| Interface        | ID           |
| ---------------- | ------------ |
| IERC5192         | 0xb45a3c0e   |
| IPactRegistry    | TBD          |
| IClaimCertificate| TBD          |
| IStakeCertificate| TBD          |

## 12. Reference Implementation (Solidity)

This is a compact, auditable reference implementation intended as a readable baseline. Production deployments SHOULD be independently audited.

See [contracts/src/StakeCertificates.sol](../contracts/src/StakeCertificates.sol) for the full implementation.

## 13. Canonical JSON Payloads (Normative Hashing)

Canonical encoding rule for any JSON hashed into content_hash, rights_root inputs, params_hash, vestingHash, conversionHash, revocationHash is RFC 8785 (JSON Canonicalization Scheme, JCS), UTF-8.

All hashes in this standard are `keccak256(JCS_bytes)`.

### 13.1 Pact JSON Example

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
    "protections": []
  },
  "custom_terms_uri": "ipfs://...",
  "custom_terms_hash": "0x..."
}
```

### 13.2 Conversion JSON Example

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

### 13.3 Vesting JSON Example

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

## 14. Security and Operational Notes

### 14.1 Authority Separation

Issuer authority should be a multisig. The reference code uses a single issuer role for simplicity.

### 14.2 Idempotence

Conforming implementations MUST be idempotent for issuance and redemption. The reference implementation enforces idempotence via issuanceId and redemptionId mappings that prevent double-mints across retries.

### 14.3 Privacy

Do not store sensitive personal data onchain. Store hashes and URIs only.

### 14.4 Upgrade Path

The reference implementation is not upgradeable. Production deployments should consider:
- Proxy patterns for upgradeability
- Migration paths between contract versions
- Emergency pause mechanisms

## 15. Compliance Stance

This standard provides a verifiable certificate record. It does not claim to be a security issuance framework, and it does not embed any jurisdictional compliance logic.

Issuers are responsible for ensuring compliance with applicable securities laws, KYC/AML requirements, and other regulatory obligations in their jurisdiction.

## 16. References

- [ERC-721: Non-Fungible Token Standard](https://eips.ethereum.org/EIPS/eip-721)
- [ERC-5192: Minimal Soulbound NFTs](https://eips.ethereum.org/EIPS/eip-5192)
- [ERC-165: Standard Interface Detection](https://eips.ethereum.org/EIPS/eip-165)
- [RFC 8785: JSON Canonicalization Scheme (JCS)](https://datatracker.ietf.org/doc/html/rfc8785)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
