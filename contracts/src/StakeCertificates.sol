// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
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
error AlreadyTransitioned();
error NotTransitioned();
error VaultAlreadySet();
error InvalidVault();
error InvalidAuthority();

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
    bool fullyRedeemed;
    uint64 issuedAt;
    uint64 redeemableAt;
    UnitType unitType;
    uint256 maxUnits;
    uint256 redeemedUnits;
    bytes32 reasonHash;
}

struct StakeState {
    bool revoked;
    uint64 issuedAt;
    uint64 vestStart;
    uint64 vestCliff;
    uint64 vestEnd;
    uint64 revokedAt;
    bool revocableUnvested;
    UnitType unitType;
    uint256 units;
    uint256 revokedUnits;
    bytes32 reasonHash;
}

// ============ Abstract Base Contract ============

/**
 * @title SoulboundERC721
 * @notice Non-transferable ERC721 base contract implementing ERC-5192
 * @dev Uses OpenZeppelin v5 _update hook to block transfers.
 *      Vault address can bypass soulbound restriction for governance seat management.
 */
abstract contract SoulboundERC721 is ERC721, IERC5192, AccessControl, Pausable {
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public immutable ISSUER;
    bytes32 public immutable ISSUER_ID;

    address internal _vault;
    string internal _baseTokenURI;

    constructor(string memory name_, string memory symbol_, address issuer_, bytes32 issuerId_) ERC721(name_, symbol_) {
        ISSUER = issuer_;
        ISSUER_ID = issuerId_;
        _grantRole(DEFAULT_ADMIN_ROLE, issuer_);
        _grantRole(ISSUER_ROLE, issuer_);
        _grantRole(PAUSER_ROLE, issuer_);
    }

    /**
     * @notice Set the vault address. Can only be called once, by the issuer.
     */
    function setVault(address vault_) external onlyRole(ISSUER_ROLE) {
        if (_vault != address(0)) revert VaultAlreadySet();
        if (vault_ == address(0)) revert InvalidVault();
        _vault = vault_;
    }

    /**
     * @notice Get the vault address
     */
    function vault() external view returns (address) {
        return _vault;
    }

    /**
     * @notice Returns whether a token is locked (soulbound)
     * @param tokenId The token ID to check
     * @return bool True if the token is locked (always true unless vault-managed)
     */
    function locked(uint256 tokenId) external view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) revert TokenNotFound();
        return true;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }

    event BaseURIUpdated(string newBaseURI);

    function setBaseURI(string calldata newBaseURI) external onlyRole(ISSUER_ROLE) {
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
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
     * @notice Pause all state-changing operations
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Override _update to enforce soulbound transfers.
     *      Minting (from == 0) and burning (to == 0) are allowed.
     *      Transfers are only allowed when initiated by the vault contract.
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from == 0). Block transfers unless vault-initiated.
        if (from != address(0) && to != address(0)) {
            _requireNotPaused();
            if (auth != _vault) revert Soulbound();
            // Vault bypass: skip standard auth check
            return super._update(to, tokenId, address(0));
        }

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
     * @notice Try to get a pact by ID. Returns (true, pact) if found, (false, empty) if not.
     */
    function tryGetPact(bytes32 pactId) external view returns (bool exists, Pact memory pact) {
        Pact storage p = _pacts[pactId];
        if (p.pactId != bytes32(0)) return (true, p);
        return (false, pact);
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
        uint256 indexed claimId,
        bytes32 indexed pactId,
        address indexed to,
        uint256 maxUnits,
        UnitType unitType,
        uint64 redeemableAt
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
        UnitType unitType,
        uint64 redeemableAt
    )
        external
        onlyRole(ISSUER_ROLE)
        whenNotPaused
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
            fullyRedeemed: false,
            issuedAt: uint64(block.timestamp),
            redeemableAt: redeemableAt,
            unitType: unitType,
            maxUnits: maxUnits,
            redeemedUnits: 0,
            reasonHash: bytes32(0)
        });

        _mintSoulbound(to, id);
        emit ClaimIssued(id, pactId, to, maxUnits, unitType, redeemableAt);
        return id;
    }

    /**
     * @notice Void a claim
     */
    function voidClaim(uint256 claimId, bytes32 reasonHash) external onlyRole(ISSUER_ROLE) whenNotPaused {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();

        ClaimState storage c = _claims[claimId];
        if (c.voided) revert AlreadyVoided();
        if (c.fullyRedeemed) revert ClaimNotRedeemable();

        // Voiding is distinct from revocation — authority can always void an unredeemed claim
        // regardless of pact revocationMode. Revocation (on stakes) is what revocationMode controls.

        c.voided = true;
        c.reasonHash = reasonHash;
        emit ClaimVoided(claimId, reasonHash);
    }

    /**
     * @notice Record a redemption against a claim (called by StakeCertificates).
     *         Supports partial redemptions — only marks fully redeemed when all units consumed.
     */
    function recordRedemption(
        uint256 claimId,
        uint256 units,
        bytes32 reasonHash
    )
        external
        onlyRole(ISSUER_ROLE)
        whenNotPaused
    {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();

        ClaimState storage c = _claims[claimId];
        if (c.voided) revert AlreadyVoided();
        if (c.fullyRedeemed) revert ClaimNotRedeemable();
        if (c.redeemedUnits + units > c.maxUnits) revert InvalidUnits();

        c.redeemedUnits += units;
        c.reasonHash = reasonHash;

        if (c.redeemedUnits == c.maxUnits) c.fullyRedeemed = true;

        emit ClaimRedeemed(claimId, reasonHash);
    }

    /**
     * @notice Get remaining redeemable units for a claim
     */
    function remainingUnits(uint256 claimId) external view returns (uint256) {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();
        ClaimState storage c = _claims[claimId];
        return c.maxUnits - c.redeemedUnits;
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
 * @notice Non-transferable stake certificates with corrected revocation logic
 */
contract SoulboundStake is SoulboundERC721 {
    StakePactRegistry public immutable REGISTRY;

    mapping(uint256 => bytes32) public stakePact;
    mapping(uint256 => StakeState) internal _stakes;

    uint256 public nextId = 1;

    event StakeMinted(
        uint256 indexed stakeId, bytes32 indexed pactId, address indexed to, uint256 units, UnitType unitType
    );
    event StakeRevoked(uint256 indexed stakeId, uint256 revokedUnits, uint256 retainedUnits, bytes32 reasonHash);

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
     * @notice Calculate vested units for a stake.
     *         For revoked stakes, returns the snapshot at revocation time.
     */
    function vestedUnits(uint256 stakeId) public view returns (uint256) {
        if (_ownerOf(stakeId) == address(0)) revert StakeNotFound();

        StakeState storage s = _stakes[stakeId];

        // Revoked stakes return the retained units (already set to vested amount at revocation)
        if (s.revoked) return s.units;

        if (block.timestamp < s.vestCliff) return 0;
        if (block.timestamp >= s.vestEnd) return s.units;

        // Linear vesting between vestStart and vestEnd
        uint256 elapsed = block.timestamp - s.vestStart;
        uint256 duration = s.vestEnd - s.vestStart;

        if (duration == 0) return s.units;

        return (s.units * elapsed) / duration;
    }

    /**
     * @notice Calculate unvested units for a stake.
     *         For revoked stakes, returns 0 (unvested portion was removed).
     */
    function unvestedUnits(uint256 stakeId) public view returns (uint256) {
        if (_ownerOf(stakeId) == address(0)) revert StakeNotFound();

        StakeState storage s = _stakes[stakeId];

        // Revoked stakes have no unvested portion
        if (s.revoked) return 0;

        return s.units - vestedUnits(stakeId);
    }

    /**
     * @notice Mint a new stake
     */
    function mintStake(
        address to,
        bytes32 pactId,
        uint256 units,
        UnitType unitType,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd,
        bool revocableUnvested
    )
        external
        onlyRole(ISSUER_ROLE)
        whenNotPaused
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
            revokedAt: 0,
            revocableUnvested: revocableUnvested,
            unitType: unitType,
            units: units,
            revokedUnits: 0,
            reasonHash: bytes32(0)
        });

        _mintSoulbound(to, id);
        emit StakeMinted(id, pactId, to, units, unitType);
        return id;
    }

    /**
     * @notice Revoke a stake.
     *         UNVESTED_ONLY: snapshots vested amount, reduces units to vested, records revoked.
     *         ANY: revokes the full stake (vested and unvested), sets units to 0.
     */
    function revokeStake(uint256 stakeId, bytes32 reasonHash) external onlyRole(ISSUER_ROLE) whenNotPaused {
        if (_ownerOf(stakeId) == address(0)) revert StakeNotFound();

        StakeState storage s = _stakes[stakeId];
        if (s.revoked) revert AlreadyRevoked();

        bytes32 pactId = stakePact[stakeId];
        Pact memory p = REGISTRY.getPact(pactId);

        if (p.revocationMode == RevocationMode.NONE) revert RevocationDisabled();

        if (p.revocationMode == RevocationMode.UNVESTED_ONLY) {
            if (!s.revocableUnvested) revert RevocationDisabled();

            // Calculate vested units at this moment
            uint256 vested = _calculateVestedUnits(s);
            if (vested >= s.units) revert StakeFullyVested();

            // Snapshot: retain vested, revoke unvested
            uint256 unvested = s.units - vested;
            s.revokedUnits = unvested;
            s.units = vested;
        } else {
            // RevocationMode.ANY: revoke everything
            s.revokedUnits = s.units;
            s.units = 0;
        }

        s.revoked = true;
        s.revokedAt = uint64(block.timestamp);
        s.reasonHash = reasonHash;
        emit StakeRevoked(stakeId, s.revokedUnits, s.units, reasonHash);
    }

    /**
     * @dev Internal vesting calculation (does not check revoked status)
     */
    function _calculateVestedUnits(StakeState storage s) internal view returns (uint256) {
        if (block.timestamp < s.vestCliff) return 0;
        if (block.timestamp >= s.vestEnd) return s.units;

        uint256 elapsed = block.timestamp - s.vestStart;
        uint256 duration = s.vestEnd - s.vestStart;
        if (duration == 0) return s.units;

        return (s.units * elapsed) / duration;
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
 * @notice Main entry point for issuing and managing stake certificates.
 *         Pre-transition: issuer controls all operations.
 *         Post-transition: issuer powers freeze permanently.
 */
contract StakeCertificates is AccessControl, Pausable {
    bytes32 public constant AUTHORITY_ROLE = keccak256("AUTHORITY_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public authority;
    bytes32 public immutable ISSUER_ID;

    StakePactRegistry public immutable REGISTRY;
    SoulboundClaim public immutable CLAIM;
    SoulboundStake public immutable STAKE;

    bool public transitioned;

    // Idempotence mappings for claims
    mapping(bytes32 => uint256) public claimIdByIssuanceId;
    mapping(bytes32 => bytes32) public claimParamsHashByIssuanceId;

    // Idempotence mappings for stakes
    mapping(bytes32 => uint256) public stakeIdByRedemptionId;
    mapping(bytes32 => bytes32) public stakeParamsHashByRedemptionId;

    event Redeemed(bytes32 indexed redemptionId, uint256 indexed claimId, uint256 indexed stakeId);
    event TransitionInitiated(address indexed vault, uint64 timestamp);
    event AuthorityTransferred(address indexed oldAuthority, address indexed newAuthority);

    modifier whenNotTransitioned() {
        if (transitioned) revert AlreadyTransitioned();
        _;
    }

    constructor(address authority_) {
        authority = authority_;
        ISSUER_ID = keccak256(abi.encode(block.chainid, authority_));

        _grantRole(DEFAULT_ADMIN_ROLE, authority_);
        _grantRole(AUTHORITY_ROLE, authority_);
        _grantRole(PAUSER_ROLE, authority_);

        // StakeCertificates is sole admin+operator on registry — no direct EOA admin surface.
        // Authority rotation on this contract covers all registry access.
        REGISTRY = new StakePactRegistry(address(this), address(this));
        CLAIM = new SoulboundClaim(address(this), ISSUER_ID, REGISTRY);
        STAKE = new SoulboundStake(address(this), ISSUER_ID, REGISTRY);
    }

    /**
     * @notice Pause all state-changing operations
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
        CLAIM.pause();
        STAKE.pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
        CLAIM.unpause();
        STAKE.unpause();
    }

    /**
     * @notice Transfer authority to a new address. Transfers all roles to new authority.
     *         Pre-transition only — post-transition, authority powers are frozen.
     */
    function transferAuthority(address newAuthority) external onlyRole(AUTHORITY_ROLE) whenNotTransitioned {
        if (newAuthority == address(0)) revert InvalidAuthority();

        address oldAuthority = authority;
        authority = newAuthority;

        // Transfer roles to new authority
        _grantRole(DEFAULT_ADMIN_ROLE, newAuthority);
        _grantRole(AUTHORITY_ROLE, newAuthority);
        _grantRole(PAUSER_ROLE, newAuthority);

        // Revoke from old authority
        _revokeRole(DEFAULT_ADMIN_ROLE, oldAuthority);
        _revokeRole(AUTHORITY_ROLE, oldAuthority);
        _revokeRole(PAUSER_ROLE, oldAuthority);

        emit AuthorityTransferred(oldAuthority, newAuthority);
    }

    /**
     * @notice Set the base URI for claim certificate metadata
     */
    function setClaimBaseURI(string calldata newBaseURI) external onlyRole(AUTHORITY_ROLE) {
        CLAIM.setBaseURI(newBaseURI);
    }

    /**
     * @notice Set the base URI for stake certificate metadata
     */
    function setStakeBaseURI(string calldata newBaseURI) external onlyRole(AUTHORITY_ROLE) {
        STAKE.setBaseURI(newBaseURI);
    }

    /**
     * @notice Initiate transition. Sets vault on child contracts and freezes issuer powers.
     * @param vault_ The vault contract address that will custody certificates post-transition.
     */
    function initiateTransition(address vault_) external onlyRole(AUTHORITY_ROLE) whenNotTransitioned whenNotPaused {
        if (vault_ == address(0)) revert InvalidVault();

        transitioned = true;

        // Set vault on child contracts so they allow vault-initiated transfers
        CLAIM.setVault(vault_);
        STAKE.setVault(vault_);

        emit TransitionInitiated(vault_, uint64(block.timestamp));
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
        whenNotTransitioned
        whenNotPaused
        returns (bytes32)
    {
        return REGISTRY.createPact(
            ISSUER_ID,
            authority,
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
        whenNotTransitioned
        whenNotPaused
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
        UnitType unitType,
        uint64 redeemableAt
    )
        external
        onlyRole(AUTHORITY_ROLE)
        whenNotTransitioned
        whenNotPaused
        returns (uint256)
    {
        bytes32 paramsHash = keccak256(abi.encode(to, pactId, maxUnits, unitType, redeemableAt));

        uint256 existing = claimIdByIssuanceId[issuanceId];
        if (existing != 0) {
            if (claimParamsHashByIssuanceId[issuanceId] != paramsHash) revert IdempotenceMismatch();
            return existing;
        }

        uint256 claimId = CLAIM.issueClaim(to, pactId, maxUnits, unitType, redeemableAt);
        claimIdByIssuanceId[issuanceId] = claimId;
        claimParamsHashByIssuanceId[issuanceId] = paramsHash;
        return claimId;
    }

    /**
     * @notice Batch issue claims for operational efficiency on L1.
     */
    function issueClaimBatch(
        bytes32[] calldata issuanceIds,
        address[] calldata recipients,
        bytes32 pactId,
        uint256[] calldata maxUnitsArr,
        UnitType unitType,
        uint64 redeemableAt
    )
        external
        onlyRole(AUTHORITY_ROLE)
        whenNotTransitioned
        whenNotPaused
        returns (uint256[] memory)
    {
        uint256 len = issuanceIds.length;
        if (len != recipients.length || len != maxUnitsArr.length) revert InvalidUnits();

        uint256[] memory claimIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            bytes32 paramsHash = keccak256(abi.encode(recipients[i], pactId, maxUnitsArr[i], unitType, redeemableAt));

            uint256 existing = claimIdByIssuanceId[issuanceIds[i]];
            if (existing != 0) {
                if (claimParamsHashByIssuanceId[issuanceIds[i]] != paramsHash) revert IdempotenceMismatch();
                claimIds[i] = existing;
            } else {
                uint256 claimId = CLAIM.issueClaim(recipients[i], pactId, maxUnitsArr[i], unitType, redeemableAt);
                claimIdByIssuanceId[issuanceIds[i]] = claimId;
                claimParamsHashByIssuanceId[issuanceIds[i]] = paramsHash;
                claimIds[i] = claimId;
            }
        }
        return claimIds;
    }

    /**
     * @notice Void a claim by issuance ID
     */
    function voidClaim(
        bytes32 issuanceId,
        bytes32 reasonHash
    )
        external
        onlyRole(AUTHORITY_ROLE)
        whenNotTransitioned
        whenNotPaused
    {
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
        UnitType unitType,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd,
        bytes32 reasonHash
    )
        external
        onlyRole(AUTHORITY_ROLE)
        whenNotTransitioned
        whenNotPaused
        returns (uint256)
    {
        bytes32 paramsHash = keccak256(abi.encode(claimId, units, unitType, vestStart, vestCliff, vestEnd, reasonHash));

        uint256 existing = stakeIdByRedemptionId[redemptionId];
        if (existing != 0) {
            if (stakeParamsHashByRedemptionId[redemptionId] != paramsHash) revert IdempotenceMismatch();
            return existing;
        }

        // Validate claim exists and is redeemable
        if (!CLAIM.exists(claimId)) revert ClaimNotFound();

        ClaimState memory c = CLAIM.getClaim(claimId);
        if (c.voided || c.fullyRedeemed) revert ClaimNotRedeemable();
        if (c.redeemableAt != 0 && block.timestamp < c.redeemableAt) revert ClaimNotRedeemable();
        if (units == 0 || units > (c.maxUnits - c.redeemedUnits)) revert InvalidUnits();
        if (unitType != c.unitType) revert InvalidUnits();

        bytes32 pactId = CLAIM.claimPact(claimId);
        Pact memory p = REGISTRY.getPact(pactId);

        address to = CLAIM.ownerOf(claimId);

        uint256 stakeId =
            STAKE.mintStake(to, pactId, units, unitType, vestStart, vestCliff, vestEnd, p.defaultRevocableUnvested);

        CLAIM.recordRedemption(claimId, units, reasonHash);

        stakeIdByRedemptionId[redemptionId] = stakeId;
        stakeParamsHashByRedemptionId[redemptionId] = paramsHash;

        emit Redeemed(redemptionId, claimId, stakeId);
        return stakeId;
    }

    /**
     * @notice Revoke a stake. Pre-transition only.
     */
    function revokeStake(
        uint256 stakeId,
        bytes32 reasonHash
    )
        external
        onlyRole(AUTHORITY_ROLE)
        whenNotTransitioned
        whenNotPaused
    {
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
