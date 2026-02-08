// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StakeCertificates, RevocationMode} from "../src/StakeCertificates.sol";

/**
 * @title DeployStakeCertificates
 * @notice Development deployment script for Stake Protocol contracts.
 *         For production, use DeployProduction which requires explicit configuration.
 *
 * Usage:
 *   # Deploy to local anvil
 *   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
 *
 *   # Deploy to Sepolia
 *   forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 *
 * Environment variables:
 *   DEPLOYER_PRIVATE_KEY - Private key for deployment
 *   AUTHORITY_ADDRESS - Address that will be the authority (optional, defaults to deployer)
 */
contract DeployStakeCertificates is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Authority defaults to deployer if not specified
        address authority = vm.envOr("AUTHORITY_ADDRESS", deployer);

        console.log("Deploying Stake Protocol...");
        console.log("Deployer:", deployer);
        console.log("Authority:", authority);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        StakeCertificates certificates = new StakeCertificates(authority);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("StakeCertificates:", address(certificates));
        console.log("StakePactRegistry:", address(certificates.REGISTRY()));
        console.log("SoulboundClaim:", address(certificates.CLAIM()));
        console.log("SoulboundStake:", address(certificates.STAKE()));
        console.log("Issuer ID:", vm.toString(certificates.ISSUER_ID()));
    }
}

/**
 * @title DeployAndCreatePact
 * @notice Development deployment with initial pact (uses fallback defaults)
 */
contract DeployAndCreatePact is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address authority = vm.envOr("AUTHORITY_ADDRESS", deployer);

        // Pact configuration from environment (defaults are for development only)
        bytes32 contentHash = vm.envOr("PACT_CONTENT_HASH", keccak256("default pact"));
        bytes32 rightsRoot = vm.envOr("PACT_RIGHTS_ROOT", keccak256("default rights"));
        string memory uri = vm.envOr("PACT_URI", string("ipfs://"));
        string memory version = vm.envOr("PACT_VERSION", string("1.0.0"));

        console.log("Deploying Stake Protocol with initial pact...");

        vm.startBroadcast(deployerPrivateKey);

        StakeCertificates certificates = new StakeCertificates(authority);

        // Create initial pact
        bytes32 pactId =
            certificates.createPact(contentHash, rightsRoot, uri, version, true, RevocationMode.UNVESTED_ONLY, true);

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("StakeCertificates:", address(certificates));
        console.log("Initial Pact ID:", vm.toString(pactId));
    }
}

/**
 * @title DeployProduction
 * @notice Production deployment script. ALL configuration must be explicitly provided.
 *         Will revert if required environment variables are missing.
 *
 * Required environment variables:
 *   DEPLOYER_PRIVATE_KEY   - Private key for deployment
 *   AUTHORITY_ADDRESS      - Authority multisig address (MUST be a multisig for mainnet)
 *   PACT_CONTENT_HASH      - keccak256 hash of pact document content
 *   PACT_RIGHTS_ROOT       - Merkle root of stakeholder rights
 *   PACT_URI               - IPFS/Arweave URI for pact document
 *   PACT_VERSION           - Semantic version string for pact
 */
contract DeployProduction is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // All required — no defaults
        address authority = vm.envAddress("AUTHORITY_ADDRESS");
        bytes32 contentHash = vm.envBytes32("PACT_CONTENT_HASH");
        bytes32 rightsRoot = vm.envBytes32("PACT_RIGHTS_ROOT");
        string memory uri = vm.envString("PACT_URI");
        string memory version = vm.envString("PACT_VERSION");

        require(authority != address(0), "AUTHORITY_ADDRESS cannot be zero");
        require(contentHash != bytes32(0), "PACT_CONTENT_HASH cannot be zero");
        require(bytes(uri).length > 7, "PACT_URI must be a valid URI (not just 'ipfs://')");

        console.log("=== PRODUCTION DEPLOYMENT ===");
        console.log("Deployer:", deployer);
        console.log("Authority:", authority);
        console.log("Chain ID:", block.chainid);
        console.log("Pact URI:", uri);
        console.log("Pact Version:", version);

        vm.startBroadcast(deployerPrivateKey);

        StakeCertificates certificates = new StakeCertificates(authority);

        bytes32 pactId =
            certificates.createPact(contentHash, rightsRoot, uri, version, true, RevocationMode.UNVESTED_ONLY, true);

        vm.stopBroadcast();

        console.log("=== Production Deployment Complete ===");
        console.log("StakeCertificates:", address(certificates));
        console.log("StakePactRegistry:", address(certificates.REGISTRY()));
        console.log("SoulboundClaim:", address(certificates.CLAIM()));
        console.log("SoulboundStake:", address(certificates.STAKE()));
        console.log("Issuer ID:", vm.toString(certificates.ISSUER_ID()));
        console.log("Initial Pact ID:", vm.toString(pactId));
    }
}
