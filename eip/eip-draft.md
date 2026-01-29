---
eip: TBD
title: Soulbound Equity Certificates
description: Non-transferable onchain ownership certificates with Pact-defined rights, vesting, and optional tokenization
author: TBD (@username)
discussions-to: https://ethereum-magicians.org/t/erc-soulbound-equity-certificates/TBD
status: Draft
type: Standards Track
category: ERC
created: 2025-01-28
requires: 165, 721, 5192
---

## Abstract

This EIP defines a minimal standard for issuing non-transferable equity certificates as verifiable, wallet-held records. The protocol models a deterministic lifecycle: **Pact → Claim → Stake → Token (optional)**. A Pact is a versioned, content-addressed agreement that defines rights and lifecycle rules. A Claim is a contingent certificate issued under a Pact. A Stake is the realized certificate after conversion. Tokenization is optional and explicitly outside the core standard.

## Motivation

Crypto projects face a structural problem: they issue liquid tokens before building lasting value. This creates misaligned incentives where stakeholders optimize for short-term price movements rather than long-term growth.

Traditional equity markets solved this decades ago. Private companies issue illiquid shares that vest over time. Founders, employees, and investors share a common outcome. Liquidity arrives only when the business has matured.

Current approaches to onchain ownership have significant limitations:

1. **Tokens as pseudo-equity**: Tokens are liquid by design, creating continuous price discovery that undermines alignment. Vesting mechanics borrowed from traditional equity ignore the economic context of immediate tradability.

2. **No standard for non-transferable ownership**: While [ERC-5192](./eip-5192.md) defines minimal soulbound semantics, there is no standard for the full lifecycle of ownership certificates including issuance, vesting, revocation, and optional tokenization.

3. **Cap table fragmentation**: Projects maintain separate offchain and onchain records, leading to divergence between legal reality and chain state.

4. **Lack of evidentiary clarity**: Existing token standards do not carry self-describing references to the rights and terms that define ownership.

This standard addresses these limitations by defining a complete ownership certificate system that separates alignment (non-liquid Stakes) from liquidity (optional future tokens).

## Specification

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in RFC 2119 and RFC 8174.

### Definitions

- **Issuer**: The issuing entity (corporation, DAO, protocol, or project).
- **Authority**: The onchain address authorized to issue, amend, convert, revoke, or void certificates.
- **Pact**: A versioned, content-addressed agreement defining rights and lifecycle rules.
- **Claim**: A non-transferable certificate representing a contingent right to receive a Stake.
- **Stake**: A non-transferable certificate representing an issued ownership position.
- **Void**: A terminal state marking a certificate as cancelled without erasing history.
- **Revoke**: Cancellation of unvested portions per Pact rules.
- **Redeem**: Conversion of a Claim to a Stake certificate.

### Core Lifecycle

The lifecycle is deterministic and flows as follows:

```
PACT CREATION → CLAIM ISSUANCE → CLAIM CONVERSION → STAKE (with vesting) → TOKEN (optional)
```

1. An Issuer defines a Pact version with deterministic content hash
2. All certificate issuance starts as a Claim
3. A Claim converts to a Stake via redemption when conditions are met
4. A Stake may include vesting metadata
5. Optional tokenization (Transition) is outside this standard

### Pact Identifiers

The `pactId` MUST be computed as:

```solidity
pactId = keccak256(abi.encode(issuerId, contentHash, keccak256(bytes(pactVersion))))
```

The `contentHash` MUST be computed as `keccak256(canonical_pact_json_bytes)` where the JSON MUST be canonicalized using RFC 8785 (JSON Canonicalization Scheme).

### Pact Structure

A Pact MUST contain the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `pactId` | `bytes32` | Computed identifier |
| `issuerId` | `bytes32` | Issuer namespace |
| `authority` | `address` | Authority address |
| `contentHash` | `bytes32` | Hash of canonical pact JSON |
| `rightsRoot` | `bytes32` | Root hash of rights schema |
| `uri` | `string` | IPFS/Arweave/HTTPS pointer to Pact content |
| `pactVersion` | `string` | Semantic version identifier |
| `mutablePact` | `bool` | Whether amendments are permitted |
| `revocationMode` | `uint8` | 0=none, 1=unvested_only, 2=any |

### Rights Schema

Rights MUST be defined in the Pact using three groups: **Power**, **Priority**, and **Protections**. Each group contains ClauseInstances.

A ClauseInstance canonical form is: `(clause_id, enabled, params_hash)`

The `rightsRoot` MUST be computed as `keccak256(canonical_rights_json_bytes)` using RFC 8785.

#### Standard Clause Registry

| Clause ID | Group | Description |
|-----------|-------|-------------|
| `PWR_VOTE` | Power | Voting weight and class vote requirement |
| `PWR_VETO` | Power | Veto rights on enumerated actions |
| `PWR_BOARD` | Power | Board seat or appointment right |
| `PRI_LIQ_PREF` | Priority | Liquidation preference |
| `PRI_DIVIDEND` | Priority | Dividend economics |
| `PRO_INFO` | Protections | Information rights |
| `PRO_PRORATA` | Protections | Pro rata participation |
| `PRO_ANTIDILUTION` | Protections | Anti-dilution protection |

### Certificate Model

Claims and Stakes MUST be non-transferable [ERC-721](./eip-721.md) tokens implementing [ERC-5192](./eip-5192.md).

#### Unit Type Enumeration

| Value | Name | Description |
|-------|------|-------------|
| 0 | SHARES | Whole share units |
| 1 | BPS | Basis points (10000 = 100%) |
| 2 | WEI | Wei-denominated fractional units |
| 3 | CUSTOM | Custom unit type defined in Pact |

#### Status Flags

The `statusFlags` field is a `uint32` bitfield:

| Bit | Name | Description |
|-----|------|-------------|
| 0 | VOIDED | Certificate has been voided |
| 1 | REVOKED | Stake has been revoked |
| 2 | REDEEMED | Claim has been converted |

#### Claim Structure

```solidity
struct ClaimState {
    bool voided;
    bool redeemed;
    uint64 issuedAt;
    uint64 redeemableAt;
    uint256 maxUnits;
    bytes32 reasonHash;
}
```

#### Stake Structure

```solidity
struct StakeState {
    bool revoked;
    uint64 issuedAt;
    uint64 vestStart;
    uint64 vestCliff;
    uint64 vestEnd;
    bool revocableUnvested;
    uint256 units;
    bytes32 reasonHash;
}
```

### Non-Transferability

Certificates MUST be non-transferable at the [ERC-721](./eip-721.md) transfer layer.

Certificates MUST block approvals (`approve` and `setApprovalForAll`).

Certificates MUST implement [ERC-5192](./eip-5192.md) and advertise the interface via [ERC-165](./eip-165.md).

### Vesting Calculation

When `revocationMode` is `UNVESTED_ONLY`, vested units MUST be calculated as:

```solidity
function vestedUnits(StakeState memory s) internal view returns (uint256) {
    if (block.timestamp < s.vestCliff) {
        return 0;
    }
    if (block.timestamp >= s.vestEnd) {
        return s.units;
    }
    uint256 elapsed = block.timestamp - s.vestStart;
    uint256 duration = s.vestEnd - s.vestStart;
    if (duration == 0) {
        return s.units;
    }
    return (s.units * elapsed) / duration;
}
```

### Idempotence Requirement

Conforming implementations MUST be idempotent for issuance and redemption. Each operation MUST accept an external identifier (`issuanceId` / `redemptionId`) and MUST prevent double-execution under retries.

### Interface

#### IPactRegistry

```solidity
interface IPactRegistry {
    event PactCreated(
        bytes32 indexed pactId,
        bytes32 indexed issuerId,
        bytes32 indexed contentHash,
        string uri,
        string pactVersion
    );

    event PactAmended(bytes32 indexed oldPactId, bytes32 indexed newPactId);

    function computePactId(
        bytes32 issuerId,
        bytes32 contentHash,
        string calldata pactVersion
    ) external pure returns (bytes32);

    function getPact(bytes32 pactId) external view returns (Pact memory);

    function pactExists(bytes32 pactId) external view returns (bool);

    function createPact(
        bytes32 issuerId,
        address authority,
        bytes32 contentHash,
        bytes32 rightsRoot,
        string calldata uri,
        string calldata pactVersion,
        bool mutablePact,
        RevocationMode revocationMode,
        bool defaultRevocableUnvested
    ) external returns (bytes32);

    function amendPact(
        bytes32 oldPactId,
        bytes32 newContentHash,
        bytes32 newRightsRoot,
        string calldata newUri,
        string calldata newPactVersion
    ) external returns (bytes32);
}
```

#### IClaimCertificate

```solidity
interface IClaimCertificate is IERC721, IERC5192 {
    event ClaimIssued(
        uint256 indexed claimId,
        bytes32 indexed pactId,
        address indexed to,
        uint256 maxUnits,
        uint64 redeemableAt
    );

    event ClaimVoided(uint256 indexed claimId, bytes32 reasonHash);

    event ClaimRedeemed(uint256 indexed claimId, bytes32 reasonHash);

    function getClaim(uint256 claimId) external view returns (ClaimState memory);

    function claimPact(uint256 claimId) external view returns (bytes32);

    function issueClaim(
        address to,
        bytes32 pactId,
        uint256 maxUnits,
        uint64 redeemableAt
    ) external returns (uint256);

    function voidClaim(uint256 claimId, bytes32 reasonHash) external;

    function markRedeemed(uint256 claimId, bytes32 reasonHash) external;
}
```

#### IStakeCertificate

```solidity
interface IStakeCertificate is IERC721, IERC5192 {
    event StakeMinted(
        uint256 indexed stakeId,
        bytes32 indexed pactId,
        address indexed to,
        uint256 units
    );

    event StakeRevoked(uint256 indexed stakeId, bytes32 reasonHash);

    function getStake(uint256 stakeId) external view returns (StakeState memory);

    function stakePact(uint256 stakeId) external view returns (bytes32);

    function vestedUnits(uint256 stakeId) external view returns (uint256);

    function unvestedUnits(uint256 stakeId) external view returns (uint256);

    function mintStake(
        address to,
        bytes32 pactId,
        uint256 units,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd,
        bool revocableUnvested
    ) external returns (uint256);

    function revokeStake(uint256 stakeId, bytes32 reasonHash) external;
}
```

### Canonical JSON Encoding

All JSON hashed into `contentHash`, `rightsRoot`, `params_hash`, or `reasonHash` MUST be canonicalized using RFC 8785 (JSON Canonicalization Scheme), UTF-8 encoded, then hashed with `keccak256`.

#### Pact JSON Example

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
  "rights": {
    "power": [{"clause_id": "PWR_VOTE", "enabled": true, "params": {"weight_bps": 10000}}],
    "priority": [],
    "protections": []
  }
}
```

## Rationale

### Why Pact → Claim → Stake?

All issuance starts as a Claim because it unifies "pending conversion" instruments (SAFE-like, vesting-based, milestone-based) with immediate issuance. The difference is only in conversion conditions. This simplifies implementation and mental models.

### Why Content-Addressed Pacts?

Content addressing ensures that the terms governing a certificate cannot change without detection. The `pactId` incorporates both the content hash and version string, making it impossible to silently modify agreement terms.

### Why Separate Certificates from Rights?

Certificates carry minimal onchain state while pointing to rights defined in Pacts. This keeps gas costs low while maintaining evidentiary clarity. Verifiers can resolve rights via the Pact reference.

### Why Non-Transferable?

Non-transferability is the core mechanism for achieving alignment. If Stakes could be sold, they would function as tokens, defeating the purpose. The [ERC-5192](./eip-5192.md) interface signals this clearly to wallets and indexers.

### Why Idempotence?

Real-world issuance involves retries, network failures, and transaction resubmission. Idempotent operations prevent double-minting and ensure consistent state regardless of delivery guarantees.

### Why Optional Tokenization?

Many projects will eventually want public liquidity. By explicitly defining tokenization as outside the core standard but providing hooks for it, this standard supports the full lifecycle without mandating token creation.

## Backwards Compatibility

This standard is fully compatible with:

- [ERC-721](./eip-721.md): Certificates are non-fungible tokens
- [ERC-5192](./eip-5192.md): Certificates implement soulbound semantics
- [ERC-165](./eip-165.md): Interface detection is supported

Existing [ERC-721](./eip-721.md) infrastructure (wallets, indexers, marketplaces) can display certificates, though transfer functionality will be blocked.

## Test Cases

Test cases are provided in the reference implementation repository. Key test scenarios include:

1. **Pact Creation**: Verify content-addressed ID computation
2. **Claim Issuance**: Verify idempotent minting and pact reference
3. **Soulbound Enforcement**: Verify transfer/approval blocking
4. **Redemption Flow**: Verify Claim → Stake conversion
5. **Vesting Calculation**: Verify cliff and linear vesting math
6. **Revocation**: Verify unvested-only revocation enforcement
7. **Interface Support**: Verify ERC-165, ERC-721, ERC-5192 compliance

## Reference Implementation

A complete reference implementation is available at:

https://github.com/stake-protocol/stake

The implementation includes:
- `StakePactRegistry`: Pact creation and amendment
- `SoulboundClaim`: Non-transferable claim certificates
- `SoulboundStake`: Non-transferable stake certificates with vesting
- `StakeCertificates`: Coordinator contract with idempotent operations

## Security Considerations

### Authority Compromise

If the Authority address is compromised, an attacker could issue unauthorized certificates or revoke existing ones. Implementations SHOULD use multisig or governance contracts for Authority.

### Front-Running

Pact creation and claim issuance may be subject to front-running. The idempotence mechanism mitigates double-minting but does not prevent information leakage.

### Content Hash Integrity

The Pact's legal meaning depends on offchain content matching the `contentHash`. Issuers MUST ensure Pact content is stored on immutable storage (IPFS, Arweave) and SHOULD pin content across multiple providers.

### Vesting Clock Manipulation

Vesting calculations depend on `block.timestamp`. While timestamp manipulation by miners/validators is limited, implementations SHOULD NOT rely on sub-minute precision.

### Revocation Scope

When `revocationMode` is `UNVESTED_ONLY`, only unvested portions can be revoked. Implementations MUST verify vesting status before revocation to prevent unauthorized cancellation of vested units.

### No Yield or Staking

Stakes MUST NOT bear yield or be used in staking mechanisms that could create transferability through wrapped derivatives. Implementations SHOULD document this restriction clearly.

### Legal Enforceability

This standard provides evidentiary records, not self-executing legal ownership. The legal meaning of Stakes depends entirely on issuer governing documents and applicable jurisdiction. Users MUST NOT assume onchain certificates confer legal rights without corresponding legal agreements.

## Copyright

Copyright and related rights waived via [CC0](../LICENSE.md).
