// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title IERC5192
 * @notice Minimal Soulbound NFT interface
 */
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);
    function locked(uint256 tokenId) external view returns (bool);
}

// ============ Errors ============

error Soulbound();
error PactImmutable();
error PactNotFound();
error PactAlreadyExists();
error ClaimNotFound();
error StakeNotFound();
error TokenNotFound();
error ClaimNotRedeemable();
error AlreadyVoided();
error AlreadyRevoked();
error RevocationDisabled();
error InvalidVesting();
error InvalidRecipient();
error InvalidUnits();
error IdempotenceMismatch();
error StakeFullyVested();

// ============ Enums ============

enum RevocationMode {
    NONE,
    UNVESTED_ONLY,
    ANY
}

enum UnitType {
    SHARES,
    BPS,
    WEI,
    CUSTOM
}

// ============ Structs ============

struct Pact {
    bytes32 pactId;
    bytes32 issuerId;
    address authority;
    bytes32 contentHash;
    bytes32 supersedesPactId;
    bytes32 rightsRoot;
    string uri;
    string pactVersion;
    bool mutablePact;
    RevocationMode revocationMode;
    bool defaultRevocableUnvested;
}

struct ClaimState {
    bool voided;
    bool redeemed;
    uint64 issuedAt;
    uint64 redeemableAt;
    uint256 maxUnits;
    bytes32 reasonHash;
}

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

// ============ Abstract Base Contract ============

/**
 * @title SoulboundERC721
 * @notice Non-transferable ERC721 base contract implementing ERC-5192
 * @dev Uses OpenZeppelin v5 _update hook to block transfers
 */
abstract contract SoulboundERC721 is ERC721, IERC5192, AccessControl {
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    address public immutable ISSUER;
    bytes32 public immutable ISSUER_ID;

    string internal _baseTokenURI;

    constructor(string memory name_, string memory symbol_, address issuer_, bytes32 issuerId_) ERC721(name_, symbol_) {
        ISSUER = issuer_;
        ISSUER_ID = issuerId_;
        _grantRole(DEFAULT_ADMIN_ROLE, issuer_);
        _grantRole(ISSUER_ROLE, issuer_);
    }

    /**
     * @notice Returns whether a token is locked (always true for soulbound tokens)
     * @param tokenId The token ID to check
     * @return bool Always returns true if token exists
     */
    function locked(uint256 tokenId) external view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) revert TokenNotFound();
        return true;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }

    function setBaseURI(string calldata newBaseURI) external onlyRole(ISSUER_ROLE) {
        _baseTokenURI = newBaseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert TokenNotFound();
        string memory base = _baseURI();
        if (bytes(base).length == 0) return "";
        return string.concat(base, Strings.toString(tokenId));
    }

    /**
     * @dev Override _update to block all transfers except minting
     * In OpenZeppelin v5, _update is called for all token operations
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0)), block transfers
        if (from != address(0) && to != address(0)) revert Soulbound();

        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Block approvals for soulbound tokens
     */
    function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal virtual override {
        if (to != address(0)) revert Soulbound();
        super._approve(to, tokenId, auth, emitEvent);
    }

    /**
     * @dev Block operator approvals for soulbound tokens
     */
    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual override {
        if (approved) revert Soulbound();
        super._setApprovalForAll(owner, operator, approved);
    }

    function _mintSoulbound(address to, uint256 tokenId) internal {
        _mint(to, tokenId);
        emit Locked(tokenId);
    }
}

// ============ Pact Registry ============

/**
 * @title StakePactRegistry
 * @notice Registry for Pact versions
 */
contract StakePactRegistry is AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    mapping(bytes32 => Pact) internal _pacts;

    event PactCreated(
        bytes32 indexed pactId, bytes32 indexed issuerId, bytes32 indexed contentHash, string uri, string pactVersion
    );
    event PactAmended(bytes32 indexed oldPactId, bytes32 indexed newPactId);

    constructor(address admin, address operator) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, operator);
    }

    /**
     * @notice Compute pact ID from components
     */
    function computePactId(
        bytes32 issuerId,
        bytes32 contentHash,
        string calldata pactVersion
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(issuerId, contentHash, keccak256(bytes(pactVersion))));
    }

    /**
     * @notice Get a Pact by ID
     * @param pactId The pact ID to look up
     * @return The Pact struct
     */
    function getPact(bytes32 pactId) external view returns (Pact memory) {
        Pact storage p = _pacts[pactId];
        if (p.pactId == bytes32(0)) revert PactNotFound();
        return p;
    }

    /**
     * @notice Check if a pact exists
     */
    function pactExists(bytes32 pactId) external view returns (bool) {
        return _pacts[pactId].pactId != bytes32(0);
    }

    /**
     * @notice Create a new Pact
     */
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
    )
        external
        onlyRole(OPERATOR_ROLE)
        returns (bytes32)
    {
        bytes32 pactId = computePactId(issuerId, contentHash, pactVersion);

        if (_pacts[pactId].pactId != bytes32(0)) revert PactAlreadyExists();

        _pacts[pactId] = Pact({
            pactId: pactId,
            issuerId: issuerId,
            authority: authority,
            contentHash: contentHash,
            supersedesPactId: bytes32(0),
            rightsRoot: rightsRoot,
            uri: uri,
            pactVersion: pactVersion,
            mutablePact: mutablePact,
            revocationMode: revocationMode,
            defaultRevocableUnvested: defaultRevocableUnvested
        });

        emit PactCreated(pactId, issuerId, contentHash, uri, pactVersion);
        return pactId;
    }

    /**
     * @notice Amend an existing Pact
     */
    function amendPact(
        bytes32 oldPactId,
        bytes32 newContentHash,
        bytes32 newRightsRoot,
        string calldata newUri,
        string calldata newPactVersion
    )
        external
        onlyRole(OPERATOR_ROLE)
        returns (bytes32)
    {
        Pact storage oldP = _pacts[oldPactId];
        if (oldP.pactId == bytes32(0)) revert PactNotFound();
        if (!oldP.mutablePact) revert PactImmutable();

        bytes32 newPactId = computePactId(oldP.issuerId, newContentHash, newPactVersion);

        if (_pacts[newPactId].pactId != bytes32(0)) revert PactAlreadyExists();

        _pacts[newPactId] = Pact({
            pactId: newPactId,
            issuerId: oldP.issuerId,
            authority: oldP.authority,
            contentHash: newContentHash,
            supersedesPactId: oldPactId,
            rightsRoot: newRightsRoot,
            uri: newUri,
            pactVersion: newPactVersion,
            mutablePact: oldP.mutablePact,
            revocationMode: oldP.revocationMode,
            defaultRevocableUnvested: oldP.defaultRevocableUnvested
        });

        emit PactAmended(oldPactId, newPactId);
        return newPactId;
    }
}

// ============ Claim Contract ============

/**
 * @title SoulboundClaim
 * @notice Non-transferable claim certificates
 */
contract SoulboundClaim is SoulboundERC721 {
    StakePactRegistry public immutable REGISTRY;

    mapping(uint256 => bytes32) public claimPact;
    mapping(uint256 => ClaimState) internal _claims;

    uint256 public nextId = 1;

    event ClaimIssued(
        uint256 indexed claimId, bytes32 indexed pactId, address indexed to, uint256 maxUnits, uint64 redeemableAt
    );
    event ClaimVoided(uint256 indexed claimId, bytes32 reasonHash);
    event ClaimRedeemed(uint256 indexed claimId, bytes32 reasonHash);

    constructor(
        address issuer_,
        bytes32 issuerId_,
        StakePactRegistry registry_
    )
        SoulboundERC721("Stake Claim", "sCLAIM", issuer_, issuerId_)
    {
        REGISTRY = registry_;
    }

    /**
     * @notice Get claim state by ID
     */
    function getClaim(uint256 claimId) external view returns (ClaimState memory) {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();
        return _claims[claimId];
    }

    /**
     * @notice Issue a new claim
     */
    function issueClaim(
        address to,
        bytes32 pactId,
        uint256 maxUnits,
        uint64 redeemableAt
    )
        external
        onlyRole(ISSUER_ROLE)
        returns (uint256)
    {
        if (to == address(0)) revert InvalidRecipient();
        if (maxUnits == 0) revert InvalidUnits();

        // Verify pact exists
        Pact memory p = REGISTRY.getPact(pactId);
        if (p.pactId == bytes32(0)) revert PactNotFound();

        uint256 id = nextId++;
        claimPact[id] = pactId;
        _claims[id] = ClaimState({
            voided: false,
            redeemed: false,
            issuedAt: uint64(block.timestamp),
            redeemableAt: redeemableAt,
            maxUnits: maxUnits,
            reasonHash: bytes32(0)
        });

        _mintSoulbound(to, id);
        emit ClaimIssued(id, pactId, to, maxUnits, redeemableAt);
        return id;
    }

    /**
     * @notice Void a claim
     */
    function voidClaim(uint256 claimId, bytes32 reasonHash) external onlyRole(ISSUER_ROLE) {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();

        ClaimState storage c = _claims[claimId];
        if (c.voided) revert AlreadyVoided();
        if (c.redeemed) revert ClaimNotRedeemable();

        bytes32 pactId = claimPact[claimId];
        Pact memory p = REGISTRY.getPact(pactId);
        if (p.revocationMode == RevocationMode.NONE) revert RevocationDisabled();

        c.voided = true;
        c.reasonHash = reasonHash;
        emit ClaimVoided(claimId, reasonHash);
    }

    /**
     * @notice Mark a claim as redeemed (called by StakeCertificates)
     */
    function markRedeemed(uint256 claimId, bytes32 reasonHash) external onlyRole(ISSUER_ROLE) {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();

        ClaimState storage c = _claims[claimId];
        if (c.voided) revert AlreadyVoided();
        if (c.redeemed) revert ClaimNotRedeemable();

        c.redeemed = true;
        c.reasonHash = reasonHash;
        emit ClaimRedeemed(claimId, reasonHash);
    }

    /**
     * @notice Check if a claim exists
     */
    function exists(uint256 claimId) external view returns (bool) {
        return _ownerOf(claimId) != address(0);
    }
}

// ============ Stake Contract ============

/**
 * @title SoulboundStake
 * @notice Non-transferable stake certificates
 */
contract SoulboundStake is SoulboundERC721 {
    StakePactRegistry public immutable REGISTRY;

    mapping(uint256 => bytes32) public stakePact;
    mapping(uint256 => StakeState) internal _stakes;

    uint256 public nextId = 1;

    event StakeMinted(uint256 indexed stakeId, bytes32 indexed pactId, address indexed to, uint256 units);
    event StakeRevoked(uint256 indexed stakeId, bytes32 reasonHash);

    constructor(
        address issuer_,
        bytes32 issuerId_,
        StakePactRegistry registry_
    )
        SoulboundERC721("Stake Certificate", "sSTAKE", issuer_, issuerId_)
    {
        REGISTRY = registry_;
    }

    /**
     * @notice Get stake state by ID
     */
    function getStake(uint256 stakeId) external view returns (StakeState memory) {
        if (_ownerOf(stakeId) == address(0)) revert StakeNotFound();
        return _stakes[stakeId];
    }

    /**
     * @notice Calculate vested units for a stake
     */
    function vestedUnits(uint256 stakeId) public view returns (uint256) {
        if (_ownerOf(stakeId) == address(0)) revert StakeNotFound();

        StakeState storage s = _stakes[stakeId];

        if (block.timestamp < s.vestCliff) return 0;
        if (block.timestamp >= s.vestEnd) return s.units;

        // Linear vesting between vestStart and vestEnd
        uint256 elapsed = block.timestamp - s.vestStart;
        uint256 duration = s.vestEnd - s.vestStart;

        if (duration == 0) return s.units;

        return (s.units * elapsed) / duration;
    }

    /**
     * @notice Calculate unvested units for a stake
     */
    function unvestedUnits(uint256 stakeId) public view returns (uint256) {
        StakeState storage s = _stakes[stakeId];
        return s.units - vestedUnits(stakeId);
    }

    /**
     * @notice Mint a new stake
     */
    function mintStake(
        address to,
        bytes32 pactId,
        uint256 units,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd,
        bool revocableUnvested
    )
        external
        onlyRole(ISSUER_ROLE)
        returns (uint256)
    {
        if (to == address(0)) revert InvalidRecipient();
        if (units == 0) revert InvalidUnits();
        if (!(vestStart <= vestCliff && vestCliff <= vestEnd)) revert InvalidVesting();

        // Verify pact exists
        Pact memory p = REGISTRY.getPact(pactId);
        if (p.pactId == bytes32(0)) revert PactNotFound();

        uint256 id = nextId++;
        stakePact[id] = pactId;
        _stakes[id] = StakeState({
            revoked: false,
            issuedAt: uint64(block.timestamp),
            vestStart: vestStart,
            vestCliff: vestCliff,
            vestEnd: vestEnd,
            revocableUnvested: revocableUnvested,
            units: units,
            reasonHash: bytes32(0)
        });

        _mintSoulbound(to, id);
        emit StakeMinted(id, pactId, to, units);
        return id;
    }

    /**
     * @notice Revoke a stake (only unvested portion if UNVESTED_ONLY mode)
     */
    function revokeStake(uint256 stakeId, bytes32 reasonHash) external onlyRole(ISSUER_ROLE) {
        if (_ownerOf(stakeId) == address(0)) revert StakeNotFound();

        StakeState storage s = _stakes[stakeId];
        if (s.revoked) revert AlreadyRevoked();

        bytes32 pactId = stakePact[stakeId];
        Pact memory p = REGISTRY.getPact(pactId);

        if (p.revocationMode == RevocationMode.NONE) revert RevocationDisabled();

        if (p.revocationMode == RevocationMode.UNVESTED_ONLY) {
            // Check that the stake has the revocableUnvested flag
            if (!s.revocableUnvested) revert RevocationDisabled();

            // Check that there are actually unvested units to revoke
            uint256 unvested = unvestedUnits(stakeId);
            if (unvested == 0) revert StakeFullyVested();
        }

        s.revoked = true;
        s.reasonHash = reasonHash;
        emit StakeRevoked(stakeId, reasonHash);
    }

    /**
     * @notice Check if a stake exists
     */
    function exists(uint256 stakeId) external view returns (bool) {
        return _ownerOf(stakeId) != address(0);
    }
}

// ============ Main Coordinator Contract ============

/**
 * @title StakeCertificates
 * @notice Main entry point for issuing and managing stake certificates
 */
contract StakeCertificates is AccessControl {
    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY_ROLE");

    address public immutable AUTHORITY;
    bytes32 public immutable ISSUER_ID;

    StakePactRegistry public immutable REGISTRY;
    SoulboundClaim public immutable CLAIM;
    SoulboundStake public immutable STAKE;

    // Idempotence mappings for claims
    mapping(bytes32 => uint256) public claimIdByIssuanceId;
    mapping(bytes32 => bytes32) public claimParamsHashByIssuanceId;

    // Idempotence mappings for stakes
    mapping(bytes32 => uint256) public stakeIdByRedemptionId;
    mapping(bytes32 => bytes32) public stakeParamsHashByRedemptionId;

    event Redeemed(bytes32 indexed redemptionId, uint256 indexed claimId, uint256 indexed stakeId);

    constructor(address authority) {
        AUTHORITY = authority;
        ISSUER_ID = keccak256(abi.encode(block.chainid, authority));

        _grantRole(DEFAULT_ADMIN_ROLE, authority);
        _grantRole(AUTHORITY_ROLE, authority);

        REGISTRY = new StakePactRegistry(authority, address(this));
        CLAIM = new SoulboundClaim(address(this), ISSUER_ID, REGISTRY);
        STAKE = new SoulboundStake(address(this), ISSUER_ID, REGISTRY);
    }

    /**
     * @notice Create a new Pact
     */
    function createPact(
        bytes32 contentHash,
        bytes32 rightsRoot,
        string calldata uri,
        string calldata pactVersion,
        bool mutablePact,
        RevocationMode revocationMode,
        bool defaultRevocableUnvested
    )
        external
        onlyRole(AUTHORITY_ROLE)
        returns (bytes32)
    {
        return REGISTRY.createPact(
            ISSUER_ID,
            AUTHORITY,
            contentHash,
            rightsRoot,
            uri,
            pactVersion,
            mutablePact,
            revocationMode,
            defaultRevocableUnvested
        );
    }

    /**
     * @notice Amend an existing Pact
     */
    function amendPact(
        bytes32 oldPactId,
        bytes32 newContentHash,
        bytes32 newRightsRoot,
        string calldata newUri,
        string calldata newPactVersion
    )
        external
        onlyRole(AUTHORITY_ROLE)
        returns (bytes32)
    {
        return REGISTRY.amendPact(oldPactId, newContentHash, newRightsRoot, newUri, newPactVersion);
    }

    /**
     * @notice Issue a claim with idempotence guarantee
     */
    function issueClaim(
        bytes32 issuanceId,
        address to,
        bytes32 pactId,
        uint256 maxUnits,
        uint64 redeemableAt
    )
        external
        onlyRole(AUTHORITY_ROLE)
        returns (uint256)
    {
        bytes32 paramsHash = keccak256(abi.encode(to, pactId, maxUnits, redeemableAt));

        uint256 existing = claimIdByIssuanceId[issuanceId];
        if (existing != 0) {
            if (claimParamsHashByIssuanceId[issuanceId] != paramsHash) revert IdempotenceMismatch();
            return existing;
        }

        uint256 claimId = CLAIM.issueClaim(to, pactId, maxUnits, redeemableAt);
        claimIdByIssuanceId[issuanceId] = claimId;
        claimParamsHashByIssuanceId[issuanceId] = paramsHash;
        return claimId;
    }

    /**
     * @notice Void a claim by issuance ID
     */
    function voidClaim(bytes32 issuanceId, bytes32 reasonHash) external onlyRole(AUTHORITY_ROLE) {
        uint256 claimId = claimIdByIssuanceId[issuanceId];
        if (claimId == 0) revert ClaimNotFound();
        CLAIM.voidClaim(claimId, reasonHash);
    }

    /**
     * @notice Redeem a claim to a stake with idempotence guarantee
     */
    function redeemToStake(
        bytes32 redemptionId,
        uint256 claimId,
        uint256 units,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd,
        bytes32 reasonHash
    )
        external
        onlyRole(AUTHORITY_ROLE)
        returns (uint256)
    {
        bytes32 paramsHash = keccak256(abi.encode(claimId, units, vestStart, vestCliff, vestEnd, reasonHash));

        uint256 existing = stakeIdByRedemptionId[redemptionId];
        if (existing != 0) {
            if (stakeParamsHashByRedemptionId[redemptionId] != paramsHash) revert IdempotenceMismatch();
            return existing;
        }

        // Validate claim exists and is redeemable
        if (!CLAIM.exists(claimId)) revert ClaimNotFound();

        ClaimState memory c = CLAIM.getClaim(claimId);
        if (c.voided || c.redeemed) revert ClaimNotRedeemable();
        if (c.redeemableAt != 0 && block.timestamp < c.redeemableAt) revert ClaimNotRedeemable();
        if (units == 0 || units > c.maxUnits) revert InvalidUnits();

        bytes32 pactId = CLAIM.claimPact(claimId);
        Pact memory p = REGISTRY.getPact(pactId);

        address to = CLAIM.ownerOf(claimId);

        uint256 stakeId = STAKE.mintStake(to, pactId, units, vestStart, vestCliff, vestEnd, p.defaultRevocableUnvested);

        CLAIM.markRedeemed(claimId, reasonHash);

        stakeIdByRedemptionId[redemptionId] = stakeId;
        stakeParamsHashByRedemptionId[redemptionId] = paramsHash;

        emit Redeemed(redemptionId, claimId, stakeId);
        return stakeId;
    }

    /**
     * @notice Revoke a stake
     */
    function revokeStake(uint256 stakeId, bytes32 reasonHash) external onlyRole(AUTHORITY_ROLE) {
        STAKE.revokeStake(stakeId, reasonHash);
    }

    /**
     * @notice Get claim by issuance ID
     */
    function getClaimByIssuanceId(bytes32 issuanceId) external view returns (uint256, ClaimState memory) {
        uint256 claimId = claimIdByIssuanceId[issuanceId];
        if (claimId == 0) revert ClaimNotFound();
        return (claimId, CLAIM.getClaim(claimId));
    }

    /**
     * @notice Get stake by redemption ID
     */
    function getStakeByRedemptionId(bytes32 redemptionId) external view returns (uint256, StakeState memory) {
        uint256 stakeId = stakeIdByRedemptionId[redemptionId];
        if (stakeId == 0) revert StakeNotFound();
        return (stakeId, STAKE.getStake(stakeId));
    }
}
