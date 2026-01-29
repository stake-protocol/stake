# Verifying Your Stake Without the App

This guide explains how to verify and interact with your Stake Protocol certificates directly onchain, without relying on any centralized application.

## Why This Matters

Stake Protocol is designed for survivability. All certificate data is stored onchain:
- **No backend dependency**: Your ownership exists in smart contract state
- **No app dependency**: Any Ethereum client can read and verify
- **No trust required**: Verify everything yourself

Even if every Stake-related website disappears, your certificates remain intact and verifiable.

## Contract Addresses

After deployment, note these addresses:

| Contract | Description |
|----------|-------------|
| `StakeCertificates` | Main coordinator contract |
| `StakePactRegistry` | Pact storage (query via main contract) |
| `SoulboundClaim` | Claim certificates (query via main contract) |
| `SoulboundStake` | Stake certificates (query via main contract) |

## Method 1: Block Explorer (Etherscan)

### Verify You Own a Certificate

1. Go to Etherscan → Contract → Read Contract
2. Find `SoulboundClaim` or `SoulboundStake` address
3. Call `ownerOf(tokenId)` with your token ID
4. Verify it returns your wallet address

### Read Certificate Details

**For Claims:**
```
Contract: SoulboundClaim
Function: getClaim(uint256 claimId)
Returns: (voided, redeemed, issuedAt, redeemableAt, maxUnits, reasonHash)
```

**For Stakes:**
```
Contract: SoulboundStake
Function: getStake(uint256 stakeId)
Returns: (revoked, issuedAt, vestStart, vestCliff, vestEnd, revocableUnvested, units, reasonHash)
```

### Check Vested Amount

```
Contract: SoulboundStake
Function: vestedUnits(uint256 stakeId)
Returns: uint256 (currently vested units)

Function: unvestedUnits(uint256 stakeId)
Returns: uint256 (currently unvested units)
```

### Read Pact Terms

```
Contract: StakePactRegistry
Function: getPact(bytes32 pactId)
Returns: Full Pact struct including uri for terms document
```

## Method 2: Command Line (cast)

Install [Foundry](https://book.getfoundry.sh/getting-started/installation) to use `cast`.

### Verify Ownership

```bash
# Check who owns a claim
cast call $CLAIM_ADDRESS "ownerOf(uint256)" $TOKEN_ID --rpc-url $RPC_URL

# Check who owns a stake
cast call $STAKE_ADDRESS "ownerOf(uint256)" $TOKEN_ID --rpc-url $RPC_URL
```

### Read Certificate State

```bash
# Read claim details
cast call $CLAIM_ADDRESS "getClaim(uint256)(bool,bool,uint64,uint64,uint256,bytes32)" $CLAIM_ID --rpc-url $RPC_URL

# Read stake details
cast call $STAKE_ADDRESS "getStake(uint256)(bool,uint64,uint64,uint64,uint64,bool,uint256,bytes32)" $STAKE_ID --rpc-url $RPC_URL
```

### Calculate Vesting

```bash
# Get vested units
cast call $STAKE_ADDRESS "vestedUnits(uint256)" $STAKE_ID --rpc-url $RPC_URL

# Get unvested units
cast call $STAKE_ADDRESS "unvestedUnits(uint256)" $STAKE_ID --rpc-url $RPC_URL
```

### Read Pact

```bash
# Get pact ID from stake
PACT_ID=$(cast call $STAKE_ADDRESS "stakePact(uint256)" $STAKE_ID --rpc-url $RPC_URL)

# Read full pact
cast call $REGISTRY_ADDRESS "getPact(bytes32)" $PACT_ID --rpc-url $RPC_URL
```

## Method 3: JavaScript/TypeScript

```javascript
import { createPublicClient, http } from 'viem';
import { mainnet } from 'viem/chains';

// Contract ABIs (minimal for verification)
const STAKE_ABI = [
  'function ownerOf(uint256 tokenId) view returns (address)',
  'function getStake(uint256 stakeId) view returns (tuple(bool revoked, uint64 issuedAt, uint64 vestStart, uint64 vestCliff, uint64 vestEnd, bool revocableUnvested, uint256 units, bytes32 reasonHash))',
  'function vestedUnits(uint256 stakeId) view returns (uint256)',
  'function unvestedUnits(uint256 stakeId) view returns (uint256)',
  'function stakePact(uint256 stakeId) view returns (bytes32)',
];

const REGISTRY_ABI = [
  'function getPact(bytes32 pactId) view returns (tuple(bytes32 pactId, bytes32 issuerId, address authority, bytes32 contentHash, bytes32 supersedesPactId, bytes32 rightsRoot, string uri, string pactVersion, bool mutablePact, uint8 revocationMode, bool defaultRevocableUnvested))',
];

const client = createPublicClient({
  chain: mainnet,
  transport: http('https://eth.llamarpc.com'),
});

async function verifyStake(stakeAddress, stakeId) {
  // Check ownership
  const owner = await client.readContract({
    address: stakeAddress,
    abi: STAKE_ABI,
    functionName: 'ownerOf',
    args: [stakeId],
  });
  console.log('Owner:', owner);

  // Get stake details
  const stake = await client.readContract({
    address: stakeAddress,
    abi: STAKE_ABI,
    functionName: 'getStake',
    args: [stakeId],
  });
  console.log('Stake:', stake);

  // Get vesting
  const vested = await client.readContract({
    address: stakeAddress,
    abi: STAKE_ABI,
    functionName: 'vestedUnits',
    args: [stakeId],
  });
  console.log('Vested Units:', vested.toString());
}
```

## Method 4: Reconstruct Cap Table from Events

All state changes emit events. You can rebuild the entire cap table from genesis:

```bash
# Get all claims issued
cast logs --from-block 0 --address $CLAIM_ADDRESS "ClaimIssued(uint256,bytes32,address,uint256,uint64)" --rpc-url $RPC_URL

# Get all stakes minted
cast logs --from-block 0 --address $STAKE_ADDRESS "StakeMinted(uint256,bytes32,address,uint256)" --rpc-url $RPC_URL

# Get all revocations
cast logs --from-block 0 --address $STAKE_ADDRESS "StakeRevoked(uint256,bytes32)" --rpc-url $RPC_URL
```

## Verifying Pact Content Integrity

The Pact stores a `contentHash` which is `keccak256` of the canonical JSON terms.

```bash
# 1. Get the Pact
cast call $REGISTRY_ADDRESS "getPact(bytes32)" $PACT_ID --rpc-url $RPC_URL
# Note the contentHash and uri fields

# 2. Fetch content from URI (e.g., IPFS)
curl "https://ipfs.io/ipfs/YOUR_CID" > pact.json

# 3. Verify hash matches (requires canonical JSON - RFC 8785)
# The hash should equal contentHash from the Pact
```

## What Each Field Means

### ClaimState
| Field | Meaning |
|-------|---------|
| `voided` | Claim was cancelled by issuer |
| `redeemed` | Claim was converted to Stake |
| `issuedAt` | Unix timestamp of issuance |
| `redeemableAt` | When claim becomes redeemable (0 = immediate) |
| `maxUnits` | Maximum units convertible to Stake |
| `reasonHash` | Hash of void/redeem reason (optional) |

### StakeState
| Field | Meaning |
|-------|---------|
| `revoked` | Stake was revoked by issuer |
| `issuedAt` | Unix timestamp of issuance |
| `vestStart` | Vesting schedule start time |
| `vestCliff` | Cliff date (0 vested before this) |
| `vestEnd` | Full vesting date |
| `revocableUnvested` | Can unvested portion be revoked? |
| `units` | Total units in this stake |
| `reasonHash` | Hash of revocation reason (optional) |

### Vesting Calculation

The contract calculates vesting as:
```
if (now < vestCliff) → 0 vested
if (now >= vestEnd) → all vested
else → units * (now - vestStart) / (vestEnd - vestStart)
```

## Public RPC Endpoints

You don't need to trust any single provider. Use any of these:

| Network | RPC URL |
|---------|---------|
| Ethereum Mainnet | `https://eth.llamarpc.com` |
| Ethereum Mainnet | `https://rpc.ankr.com/eth` |
| Ethereum Mainnet | `https://cloudflare-eth.com` |
| Sepolia Testnet | `https://rpc.sepolia.org` |

Or run your own node for maximum trustlessness.

## Summary

Your Stake Protocol certificates are:

1. **Stored entirely onchain** - No backend required
2. **Readable by anyone** - Standard ERC-721 + custom getters
3. **Verifiable from events** - Full history reconstructable
4. **Protected by Ethereum** - Same security as ETH itself

The Stake app is a convenience layer. Your ownership exists independently of any application.
