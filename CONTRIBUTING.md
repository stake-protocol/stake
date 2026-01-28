# Contributing to Stake Protocol

Thank you for your interest in contributing to Stake Protocol. This document provides guidelines and information for contributors.

## How to Contribute

### Reporting Issues

- Check existing issues before creating a new one
- Use a clear, descriptive title
- Provide detailed reproduction steps for bugs
- Include relevant logs, screenshots, or code snippets

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make your changes
4. Write or update tests as needed
5. Ensure all tests pass
6. Commit with clear, descriptive messages
7. Push to your fork
8. Open a Pull Request

### Pull Request Guidelines

- Reference any related issues
- Provide a clear description of changes
- Keep changes focused and atomic
- Update documentation as needed
- Ensure CI passes

## Development Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+ (for tooling)

### Building Contracts

```bash
cd contracts
forge install
forge build
```

### Running Tests

```bash
cd contracts
forge test
```

### Code Style

- Solidity: Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Use `forge fmt` for formatting
- Keep functions focused and well-documented
- Prefer explicit over implicit

## Specification Changes

Changes to the protocol specification (`spec/STAKE-PROTOCOL.md`) require:

1. Discussion in an issue first
2. Clear rationale for the change
3. Consideration of backwards compatibility
4. Updates to reference implementation if needed

## Security

If you discover a security vulnerability, please do NOT open a public issue. Instead, see [SECURITY.md](SECURITY.md) for responsible disclosure instructions.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

Open a discussion or issue if you have questions about contributing.
