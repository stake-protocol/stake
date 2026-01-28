# Stake Protocol

**Soulbound Equity Certificates (SEC) for Onchain Ownership**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Stake Protocol defines a minimal onchain standard for issuing non-transferable equity certificates as verifiable, wallet-held records. The protocol models a deterministic lifecycle:

**Pact → Claim → Stake → Token (optional)**

## Overview

- **Pact**: A versioned, content-addressed agreement that defines rights, issuer powers, amendment rules, revocation rules, and dispute terms
- **Claim**: A contingent certificate issued under a Pact, representing a right to receive a Stake
- **Stake**: A realized certificate representing an issued ownership position

The standard is designed to:
1. Provide evidentiary clarity with self-describing references to rights
2. Minimize user actions with issuer-driven minting
3. Enable controlled flexibility through explicit Pact rules

## Repository Structure

```
stake/
├── spec/                    # Protocol specification
│   └── STAKE-PROTOCOL.md   # Full specification document
├── contracts/              # Solidity smart contracts
│   └── src/
│       └── StakeCertificates.sol
└── LICENSE
```

## Specification

See [spec/STAKE-PROTOCOL.md](spec/STAKE-PROTOCOL.md) for the complete protocol specification, including:

- Core lifecycle and semantics
- Pact model with rights schema
- Certificate model (Claims and Stakes)
- Funding and minting rules
- Amendment and revocation mechanics
- Reference implementation

## Key Features

### Non-Transferable (Soulbound)

Certificates are non-transferable ERC-721 tokens implementing [ERC-5192](https://eips.ethereum.org/EIPS/eip-5192). They cannot be sold, traded, or transferred—they represent a verifiable record of an ownership relationship.

### Content-Addressed Agreements

Pacts use deterministic content hashing ([RFC 8785 JCS](https://datatracker.ietf.org/doc/html/rfc8785)) to ensure verifiability and immutability of agreement terms.

### Idempotent Operations

All issuance and redemption operations are idempotent, supporting safe retries without risk of double-minting.

### Flexible Rights Schema

The standardized rights schema covers:
- **Power**: Voting, veto, board seats, delegation
- **Priority**: Liquidation preferences, dividends, conversion
- **Protections**: Information rights, pro-rata, anti-dilution, lockups

## Quick Start

### Installation

```bash
# Using Foundry
forge install stake-protocol/stake

# Or copy contracts directly
cp contracts/src/StakeCertificates.sol your-project/src/
```

### Dependencies

The reference implementation uses:
- OpenZeppelin Contracts v5.x (`@openzeppelin/contracts`)
- Solidity ^0.8.23

### Basic Usage

```solidity
// Deploy the protocol
StakeCertificates certificates = new StakeCertificates(authorityAddress);

// Create a Pact
bytes32 pactId = certificates.createPact(
    contentHash,      // keccak256 of canonical Pact JSON
    rightsRoot,       // keccak256 of canonical rights JSON
    "ipfs://...",     // URI to Pact document
    "1.0.0",          // Pact version
    true,             // mutable
    RevocationMode.UNVESTED_ONLY,
    true              // defaultRevocableUnvested
);

// Issue a Claim
uint256 claimId = certificates.issueClaim(
    issuanceId,       // Unique idempotence key
    recipientAddress,
    pactId,
    1000,             // maxUnits
    0                 // redeemableAt (0 = immediate)
);

// Redeem Claim to Stake
uint256 stakeId = certificates.redeemToStake(
    redemptionId,     // Unique idempotence key
    claimId,
    1000,             // units
    vestStart,
    vestCliff,
    vestEnd,
    bytes32(0)        // reasonHash
);
```

## Standards Compliance

- [ERC-721](https://eips.ethereum.org/EIPS/eip-721): Non-Fungible Token Standard
- [ERC-5192](https://eips.ethereum.org/EIPS/eip-5192): Minimal Soulbound NFTs
- [ERC-165](https://eips.ethereum.org/EIPS/eip-165): Standard Interface Detection
- [RFC 8785](https://datatracker.ietf.org/doc/html/rfc8785): JSON Canonicalization Scheme

## Security

The reference implementation is provided for educational and development purposes. **Production deployments should be independently audited.**

Key security considerations:
- Authority should be a multisig
- Pact immutability is enforced at the contract level
- Idempotence prevents double-minting attacks

## Contributing

Contributions are welcome. Please:
1. Open an issue to discuss proposed changes
2. Follow the existing code style
3. Include tests for new functionality
4. Update documentation as needed

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Links

- [Specification](spec/STAKE-PROTOCOL.md)
- [EIP Discussion](https://ethereum-magicians.org/) (Coming Soon)
