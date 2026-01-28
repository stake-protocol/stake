# CLAUDE.md - AI Assistant Guide for Stake Protocol

## Project Overview

Stake is a decentralized ownership system for crypto startups that replaces "token = equity" with non-transferable onchain ownership certificates. This is an early-stage project (v0.x) with schemas stabilizing.

## Core Domain Concepts

Understanding these primitives is essential for working on this codebase:

- **Stake**: Non-transferable ownership certificate with governance + distributions (as configured)
- **Claim**: Non-transferable claim that can be redeemed into Stake (no governance until redeemed)
- **Pact**: Immutable onchain agreement defining terms between an issuer and counterparties

### Lifecycle Events

- **Redeem**: Claim → Stake transition
- **Transition**: Private Stake/Claims → public tokenization event (optional; separate from Redeem)

## Repository Structure

```
stake/
├── spec/        # Protocol schemas and specifications
├── contracts/   # Smart contracts
├── sdk/         # TypeScript SDK and types
├── app/         # Commercial app (may be private or excluded)
├── CLAUDE.md    # This file
├── README.md    # Project overview
├── LICENSE      # MIT License
└── .gitignore   # Node.js/TypeScript gitignore
```

## Technology Stack

Based on project configuration, this codebase uses:

- **Runtime**: Node.js
- **Language**: TypeScript
- **Package Manager**: npm/yarn/pnpm supported
- **Build Tools**: Vite (likely)
- **Smart Contracts**: Blockchain platform TBD

## Development Commands

<!-- Commands will be added as implementation progresses -->
```bash
# Install dependencies
npm install

# Build the project
npm run build

# Run tests
npm test

# Lint code
npm run lint
```

## Code Conventions

### TypeScript

- Use strict TypeScript configuration
- Prefer interfaces over types for object shapes
- Export types alongside implementations
- Use descriptive names that reflect domain concepts (Stake, Claim, Pact, etc.)

### File Naming

- Use kebab-case for file names: `stake-certificate.ts`
- Use PascalCase for class/interface files when single export: `StakeCertificate.ts`
- Test files: `*.test.ts` or `*.spec.ts`

### Smart Contracts

- Follow security-first development practices
- Document all public functions
- Include comprehensive test coverage
- Use established patterns for ownership and access control

## Architecture Guidelines

### SDK Development (`sdk/`)

- Expose clean, typed APIs for interacting with the protocol
- Provide helper functions for common operations
- Include TypeScript type definitions
- Support both browser and Node.js environments

### Protocol Schemas (`spec/`)

- Define schemas using standard formats (JSON Schema, Protocol Buffers, etc.)
- Version all schema changes
- Document breaking changes

### Smart Contracts (`contracts/`)

- Implement core primitives: Stake, Claim, Pact
- Non-transferable tokens require special ERC patterns (e.g., ERC-5192 for soulbound)
- Pact immutability is critical - no upgrade patterns for agreement terms

## Testing Guidelines

- Write unit tests for all SDK functions
- Write integration tests for contract interactions
- Use property-based testing for critical financial logic
- Test edge cases around redemption and transitions

## Security Considerations

- Stake and Claim are explicitly non-transferable - enforce this rigorously
- Pacts are immutable once created - no admin overrides
- Validate all inputs at system boundaries
- Follow blockchain security best practices (reentrancy guards, etc.)

## Git Workflow

- Main branch contains stable releases
- Feature branches for development
- Commit messages should be descriptive and reference domain concepts
- Keep commits atomic and focused

## Common Tasks

### Adding a New Schema
1. Define schema in `spec/`
2. Generate TypeScript types for `sdk/`
3. Update contract interfaces if needed

### Implementing a New Contract Feature
1. Design the interface first
2. Write tests before implementation
3. Implement with security in mind
4. Document public functions

### SDK Changes
1. Maintain backward compatibility when possible
2. Update TypeScript types
3. Add/update tests
4. Update documentation

## Project Status

**Current Phase**: v0.x (schemas stabilizing)

This is an early-stage project. When contributing:
- Expect schemas and APIs to evolve
- Prioritize correctness over optimization
- Document design decisions
- Raise concerns about architectural choices early

## License

MIT License - See LICENSE file for details.
