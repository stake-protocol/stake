// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StakeCertificates, RevocationMode} from "../src/StakeCertificates.sol";

/**
 * @title DeployStakeCertificates
 * @notice Deployment script for Stake Protocol contracts
 *
 * Usage:
 *   # Deploy to local anvil
 *   forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
 *
 *   # Deploy to Sepolia
 *   forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 *
 *   # Deploy to Mainnet
 *   forge script script/Deploy.s.sol --rpc-url $ETH_RPC_URL --broadcast --verify
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
 * @notice Deploys contracts and creates an initial pact
 */
contract DeployAndCreatePact is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address authority = vm.envOr("AUTHORITY_ADDRESS", deployer);

        // Pact configuration from environment
        bytes32 contentHash = vm.envOr("PACT_CONTENT_HASH", keccak256("default pact"));
        bytes32 rightsRoot = vm.envOr("PACT_RIGHTS_ROOT", keccak256("default rights"));
        string memory uri = vm.envOr("PACT_URI", string("ipfs://"));
        string memory version = vm.envOr("PACT_VERSION", string("1.0.0"));

        console.log("Deploying Stake Protocol with initial pact...");

        vm.startBroadcast(deployerPrivateKey);

        StakeCertificates certificates = new StakeCertificates(authority);

        // Create initial pact
        bytes32 pactId = certificates.createPact(
            contentHash,
            rightsRoot,
            uri,
            version,
            true, // mutable
            RevocationMode.UNVESTED_ONLY,
            true // defaultRevocableUnvested
        );

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("StakeCertificates:", address(certificates));
        console.log("Initial Pact ID:", vm.toString(pactId));
    }
}
