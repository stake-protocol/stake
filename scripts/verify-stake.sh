#!/bin/bash
# Stake Protocol - Certificate Verification Script
# Verify your certificates without the Stake app
#
# Requirements: cast (from Foundry) - https://book.getfoundry.sh
#
# Usage:
#   ./verify-stake.sh <stake_contract> <token_id> [rpc_url]
#
# Example:
#   ./verify-stake.sh 0x1234...5678 1 https://eth.llamarpc.com

set -e

STAKE_ADDRESS=$1
TOKEN_ID=$2
RPC_URL=${3:-"https://eth.llamarpc.com"}

if [ -z "$STAKE_ADDRESS" ] || [ -z "$TOKEN_ID" ]; then
    echo "Usage: ./verify-stake.sh <stake_contract> <token_id> [rpc_url]"
    exit 1
fi

echo "============================================"
echo "Stake Protocol - Certificate Verification"
echo "============================================"
echo ""
echo "Contract: $STAKE_ADDRESS"
echo "Token ID: $TOKEN_ID"
echo "RPC URL:  $RPC_URL"
echo ""

# Check ownership
echo "--- Ownership ---"
OWNER=$(cast call "$STAKE_ADDRESS" "ownerOf(uint256)(address)" "$TOKEN_ID" --rpc-url "$RPC_URL" 2>/dev/null || echo "NOT_FOUND")
echo "Owner: $OWNER"
echo ""

if [ "$OWNER" = "NOT_FOUND" ]; then
    echo "Error: Token does not exist"
    exit 1
fi

# Get stake details
echo "--- Stake Details ---"
STAKE=$(cast call "$STAKE_ADDRESS" "getStake(uint256)" "$TOKEN_ID" --rpc-url "$RPC_URL" 2>/dev/null)
echo "Raw data: $STAKE"
echo ""

# Get vesting info
echo "--- Vesting Status ---"
VESTED=$(cast call "$STAKE_ADDRESS" "vestedUnits(uint256)(uint256)" "$TOKEN_ID" --rpc-url "$RPC_URL" 2>/dev/null)
UNVESTED=$(cast call "$STAKE_ADDRESS" "unvestedUnits(uint256)(uint256)" "$TOKEN_ID" --rpc-url "$RPC_URL" 2>/dev/null)
echo "Vested Units:   $VESTED"
echo "Unvested Units: $UNVESTED"
echo ""

# Get pact reference
echo "--- Pact Reference ---"
PACT_ID=$(cast call "$STAKE_ADDRESS" "stakePact(uint256)(bytes32)" "$TOKEN_ID" --rpc-url "$RPC_URL" 2>/dev/null)
echo "Pact ID: $PACT_ID"
echo ""

# Check if locked (soulbound)
echo "--- Soulbound Status ---"
LOCKED=$(cast call "$STAKE_ADDRESS" "locked(uint256)(bool)" "$TOKEN_ID" --rpc-url "$RPC_URL" 2>/dev/null)
echo "Locked (non-transferable): $LOCKED"
echo ""

echo "============================================"
echo "Verification complete."
echo "This certificate exists onchain and is"
echo "verifiable without any centralized app."
echo "============================================"
