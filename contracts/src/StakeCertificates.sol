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
error ClaimFullyVested();
error AlreadyTransitioned();
error VaultAlreadySet();
error InvalidVault();
error InvalidAuthority();
error ArrayLengthMismatch();
error NothingToRedeem();
error NotHolder();
error RecipientNotSmartWallet();

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
}

struct ClaimState {
    bool voided;
    uint64 issuedAt;
    uint64 redeemableAt;
    uint64 vestStart;
    uint64 vestCliff;
    uint64 vestEnd;
    uint64 revokedAt;
    UnitType unitType;
    uint256 maxUnits;
    uint256 redeemedUnits;
    bytes32 reasonHash;
}

struct StakeState {
    uint64 issuedAt;
    UnitType unitType;
    uint256 units;
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
        RevocationMode revocationMode
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
            revocationMode: revocationMode
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
            revocationMode: oldP.revocationMode
        });

        emit PactAmended(oldPactId, newPactId);
        return newPactId;
    }
}

// ============ Claim Contract ============

/**
 * @title SoulboundClaim
 * @notice Non-transferable claim certificates with optional vesting.
 *         Claims are the universal issuance envelope — SAFEs, stock options,
 *         warrants, RSUs, and advisor grants all collapse into a single primitive.
 *         Vesting and revocation happen at the Claim level.
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
        uint64 redeemableAt,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd
    );
    event ClaimVoided(uint256 indexed claimId, bytes32 reasonHash);
    event ClaimRevoked(uint256 indexed claimId, uint256 vestedAtRevocation, bytes32 reasonHash);
    event ClaimRedeemed(uint256 indexed claimId, uint256 units, bytes32 reasonHash);

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
     * @notice Issue a new claim with optional vesting schedule.
     *         For SAFEs/conversions: set vestStart=vestCliff=vestEnd=0 (no vesting, use redeemableAt).
     *         For options/RSUs: set vesting schedule (vestStart, vestCliff, vestEnd).
     *         Both gates can coexist — units must be vested AND past redeemableAt to redeem.
     */
    function issueClaim(
        address to,
        bytes32 pactId,
        uint256 maxUnits,
        UnitType unitType,
        uint64 redeemableAt,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd
    )
        external
        onlyRole(ISSUER_ROLE)
        whenNotPaused
        returns (uint256)
    {
        if (to == address(0)) revert InvalidRecipient();
        if (maxUnits == 0) revert InvalidUnits();
        // Vesting params: either all zero (no vesting) or valid order
        if (vestEnd != 0) {
            if (!(vestStart <= vestCliff && vestCliff <= vestEnd)) revert InvalidVesting();
        }

        // Verify pact exists (getPact reverts if not found)
        REGISTRY.getPact(pactId);

        uint256 id = nextId++;
        claimPact[id] = pactId;
        _claims[id] = ClaimState({
            voided: false,
            issuedAt: uint64(block.timestamp),
            redeemableAt: redeemableAt,
            vestStart: vestStart,
            vestCliff: vestCliff,
            vestEnd: vestEnd,
            revokedAt: 0,
            unitType: unitType,
            maxUnits: maxUnits,
            redeemedUnits: 0,
            reasonHash: bytes32(0)
        });

        _mintSoulbound(to, id);
        emit ClaimIssued(id, pactId, to, maxUnits, unitType, redeemableAt, vestStart, vestCliff, vestEnd);
        return id;
    }

    /**
     * @notice Calculate vested units for a claim.
     *         If no vesting is set (vestEnd == 0), all units are considered vested.
     *         If revoked, vesting is frozen at the revocation timestamp.
     */
    function vestedUnits(uint256 claimId) public view returns (uint256) {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();
        ClaimState storage c = _claims[claimId];
        return _calculateVestedUnits(c);
    }

    /**
     * @notice Calculate unvested units for a claim.
     */
    function unvestedUnits(uint256 claimId) public view returns (uint256) {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();
        ClaimState storage c = _claims[claimId];
        return c.maxUnits - _calculateVestedUnits(c);
    }

    /**
     * @notice Calculate redeemable units (vested minus already redeemed).
     */
    function redeemableUnits(uint256 claimId) public view returns (uint256) {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();
        ClaimState storage c = _claims[claimId];
        if (c.voided) return 0;
        uint256 vested = _calculateVestedUnits(c);
        if (vested <= c.redeemedUnits) return 0;
        return vested - c.redeemedUnits;
    }

    /**
     * @notice Void a claim. Authority can always void an unredeemed claim regardless
     *         of revocationMode — this is the safety valve for mistakes.
     */
    function voidClaim(uint256 claimId, bytes32 reasonHash) external onlyRole(ISSUER_ROLE) whenNotPaused {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();

        ClaimState storage c = _claims[claimId];
        if (c.voided) revert AlreadyVoided();
        if (c.redeemedUnits == c.maxUnits) revert ClaimNotRedeemable();

        c.voided = true;
        c.reasonHash = reasonHash;
        emit ClaimVoided(claimId, reasonHash);
    }

    /**
     * @notice Revoke a claim's unvested units. Freezes vesting at the current timestamp.
     *         Requires RevocationMode.UNVESTED_ONLY or ANY on the pact.
     *         UNVESTED_ONLY: freezes vesting, vested units remain redeemable.
     *         ANY: voids the claim entirely (even vested but unredeemed units are lost).
     */
    function revokeClaim(uint256 claimId, bytes32 reasonHash) external onlyRole(ISSUER_ROLE) whenNotPaused {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();

        ClaimState storage c = _claims[claimId];
        if (c.voided) revert AlreadyVoided();
        if (c.revokedAt != 0) revert AlreadyRevoked();

        bytes32 pactId = claimPact[claimId];
        Pact memory p = REGISTRY.getPact(pactId);

        if (p.revocationMode == RevocationMode.NONE) revert RevocationDisabled();

        if (p.revocationMode == RevocationMode.ANY) {
            // ANY mode: void the claim entirely
            c.voided = true;
            c.reasonHash = reasonHash;
            emit ClaimVoided(claimId, reasonHash);
            return;
        }

        // UNVESTED_ONLY: freeze vesting at current timestamp
        uint256 vested = _calculateVestedUnits(c);
        if (vested >= c.maxUnits) revert ClaimFullyVested();

        c.revokedAt = uint64(block.timestamp);
        c.reasonHash = reasonHash;
        emit ClaimRevoked(claimId, vested, reasonHash);
    }

    /**
     * @notice Record a redemption against a claim (called by StakeCertificates).
     *         Only redeems vested units.
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

        uint256 vested = _calculateVestedUnits(c);
        uint256 available = vested - c.redeemedUnits;
        if (units == 0 || units > available) revert InvalidUnits();

        c.redeemedUnits += units;
        c.reasonHash = reasonHash;

        emit ClaimRedeemed(claimId, units, reasonHash);
    }

    /**
     * @notice Get remaining redeemable units for a claim
     */
    function remainingUnits(uint256 claimId) external view returns (uint256) {
        if (_ownerOf(claimId) == address(0)) revert ClaimNotFound();
        ClaimState storage c = _claims[claimId];
        if (c.voided) return 0;
        uint256 vested = _calculateVestedUnits(c);
        if (vested <= c.redeemedUnits) return 0;
        return vested - c.redeemedUnits;
    }

    /**
     * @notice Check if a claim exists
     */
    function exists(uint256 claimId) external view returns (bool) {
        return _ownerOf(claimId) != address(0);
    }

    /**
     * @dev Internal vesting calculation.
     *      If vestEnd == 0, all units are vested (no vesting schedule).
     *      If revokedAt > 0, vesting is frozen at that timestamp.
     */
    function _calculateVestedUnits(ClaimState storage c) internal view returns (uint256) {
        // No vesting schedule — all units vested immediately
        if (c.vestEnd == 0) return c.maxUnits;

        // Use revocation timestamp if claim was revoked (freeze vesting)
        uint256 timestamp = c.revokedAt != 0 ? c.revokedAt : block.timestamp;

        if (timestamp < c.vestCliff) return 0;
        if (timestamp >= c.vestEnd) return c.maxUnits;

        // Linear vesting between vestStart and vestEnd
        uint256 elapsed = timestamp - c.vestStart;
        uint256 duration = c.vestEnd - c.vestStart;
        if (duration == 0) return c.maxUnits;

        return (c.maxUnits * elapsed) / duration;
    }
}

// ============ Stake Contract ============

/**
 * @title SoulboundStake
 * @notice Non-transferable stake certificates representing confirmed, unconditional ownership.
 *         A Stake is a fact — no vesting, no revocation. Once minted, it is yours forever.
 */
contract SoulboundStake is SoulboundERC721 {
    StakePactRegistry public immutable REGISTRY;

    mapping(uint256 => bytes32) public stakePact;
    mapping(uint256 => StakeState) internal _stakes;

    uint256 public nextId = 1;

    event StakeMinted(
        uint256 indexed stakeId, bytes32 indexed pactId, address indexed to, uint256 units, UnitType unitType
    );
    event StakeBurned(uint256 indexed stakeId, address indexed holder);

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
     * @notice Mint a new stake. Stakes are unconditional — no vesting, no revocation.
     */
    function mintStake(
        address to,
        bytes32 pactId,
        uint256 units,
        UnitType unitType
    )
        external
        onlyRole(ISSUER_ROLE)
        whenNotPaused
        returns (uint256)
    {
        if (to == address(0)) revert InvalidRecipient();
        if (units == 0) revert InvalidUnits();

        // Verify pact exists (getPact reverts if not found)
        REGISTRY.getPact(pactId);

        uint256 id = nextId++;
        stakePact[id] = pactId;
        _stakes[id] = StakeState({
            issuedAt: uint64(block.timestamp),
            unitType: unitType,
            units: units,
            reasonHash: bytes32(0)
        });

        _mintSoulbound(to, id);
        emit StakeMinted(id, pactId, to, units, unitType);
        return id;
    }

    /**
     * @notice Holder burns their own stake. Irreversible.
     *         Only the current holder can call this.
     */
    function burn(uint256 stakeId) external {
        if (ownerOf(stakeId) != msg.sender) revert NotHolder();
        delete _stakes[stakeId];
        delete stakePact[stakeId];
        _burn(stakeId);
        emit StakeBurned(stakeId, msg.sender);
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
 *
 *         Lifecycle: Pact → Claim (vests) → Stake (unconditional ownership) → Token (optional)
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
     * @notice Pause all state-changing operations. Pre-transition only.
     */
    function pause() external onlyRole(PAUSER_ROLE) whenNotTransitioned {
        _pause();
        CLAIM.pause();
        STAKE.pause();
    }

    /**
     * @notice Unpause operations. Pre-transition only.
     */
    function unpause() external onlyRole(PAUSER_ROLE) whenNotTransitioned {
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
     * @notice Set the base URI for claim certificate metadata. Pre-transition only.
     */
    function setClaimBaseURI(string calldata newBaseURI) external onlyRole(AUTHORITY_ROLE) whenNotTransitioned {
        CLAIM.setBaseURI(newBaseURI);
    }

    /**
     * @notice Set the base URI for stake certificate metadata. Pre-transition only.
     */
    function setStakeBaseURI(string calldata newBaseURI) external onlyRole(AUTHORITY_ROLE) whenNotTransitioned {
        STAKE.setBaseURI(newBaseURI);
    }

    /**
     * @notice Initiate transition. Sets vault on child contracts, permanently revokes all
     *         issuer powers, and ensures child contracts are unpaused for vault operations.
     *         This is irreversible — after this call, the authority has zero control.
     * @param vault_ The vault contract address that will custody certificates post-transition.
     */
    function initiateTransition(address vault_) external onlyRole(AUTHORITY_ROLE) whenNotTransitioned whenNotPaused {
        if (vault_ == address(0)) revert InvalidVault();

        transitioned = true;

        // Set vault on child contracts so they allow vault-initiated transfers
        CLAIM.setVault(vault_);
        STAKE.setVault(vault_);

        // Ensure child contracts are unpaused — vault operations must be unstoppable
        if (CLAIM.paused()) CLAIM.unpause();
        if (STAKE.paused()) STAKE.unpause();

        // Permanently revoke ALL authority roles — issuer powers freeze forever.
        // After this, no EOA holds any role on this contract.
        _revokeRole(PAUSER_ROLE, authority);
        _revokeRole(AUTHORITY_ROLE, authority);
        _revokeRole(DEFAULT_ADMIN_ROLE, authority);

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
        RevocationMode revocationMode
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
            revocationMode
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
     * @notice Issue a claim with idempotence guarantee and optional vesting.
     */
    function issueClaim(
        bytes32 issuanceId,
        address to,
        bytes32 pactId,
        uint256 maxUnits,
        UnitType unitType,
        uint64 redeemableAt,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd
    )
        external
        onlyRole(AUTHORITY_ROLE)
        whenNotTransitioned
        whenNotPaused
        returns (uint256)
    {
        if (to.code.length == 0) revert RecipientNotSmartWallet();

        bytes32 paramsHash = keccak256(abi.encode(to, pactId, maxUnits, unitType, redeemableAt, vestStart, vestCliff, vestEnd));

        uint256 existing = claimIdByIssuanceId[issuanceId];
        if (existing != 0) {
            if (claimParamsHashByIssuanceId[issuanceId] != paramsHash) revert IdempotenceMismatch();
            return existing;
        }

        uint256 claimId = CLAIM.issueClaim(to, pactId, maxUnits, unitType, redeemableAt, vestStart, vestCliff, vestEnd);
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
        uint64 redeemableAt,
        uint64 vestStart,
        uint64 vestCliff,
        uint64 vestEnd
    )
        external
        onlyRole(AUTHORITY_ROLE)
        whenNotTransitioned
        whenNotPaused
        returns (uint256[] memory)
    {
        uint256 len = issuanceIds.length;
        if (len != recipients.length || len != maxUnitsArr.length) revert ArrayLengthMismatch();

        uint256[] memory claimIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            if (recipients[i].code.length == 0) revert RecipientNotSmartWallet();
            bytes32 paramsHash = keccak256(abi.encode(recipients[i], pactId, maxUnitsArr[i], unitType, redeemableAt, vestStart, vestCliff, vestEnd));

            uint256 existing = claimIdByIssuanceId[issuanceIds[i]];
            if (existing != 0) {
                if (claimParamsHashByIssuanceId[issuanceIds[i]] != paramsHash) revert IdempotenceMismatch();
                claimIds[i] = existing;
            } else {
                uint256 claimId = CLAIM.issueClaim(recipients[i], pactId, maxUnitsArr[i], unitType, redeemableAt, vestStart, vestCliff, vestEnd);
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
     * @notice Revoke a claim by issuance ID. Freezes vesting (UNVESTED_ONLY) or voids (ANY).
     */
    function revokeClaim(
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
        CLAIM.revokeClaim(claimId, reasonHash);
    }

    /**
     * @notice Redeem vested claim units to a stake. Stakes are unconditional ownership.
     *         Vesting is validated on the Claim — only vested units can be redeemed.
     */
    function redeemToStake(
        bytes32 redemptionId,
        uint256 claimId,
        uint256 units,
        bytes32 reasonHash
    )
        external
        onlyRole(AUTHORITY_ROLE)
        whenNotTransitioned
        whenNotPaused
        returns (uint256)
    {
        bytes32 paramsHash = keccak256(abi.encode(claimId, units, reasonHash));

        uint256 existing = stakeIdByRedemptionId[redemptionId];
        if (existing != 0) {
            if (stakeParamsHashByRedemptionId[redemptionId] != paramsHash) revert IdempotenceMismatch();
            return existing;
        }

        // Validate claim exists and is redeemable
        if (!CLAIM.exists(claimId)) revert ClaimNotFound();

        ClaimState memory c = CLAIM.getClaim(claimId);
        if (c.voided) revert ClaimNotRedeemable();
        if (c.redeemableAt != 0 && block.timestamp < c.redeemableAt) revert ClaimNotRedeemable();
        if (units == 0) revert InvalidUnits();

        bytes32 pactId = CLAIM.claimPact(claimId);
        address to = CLAIM.ownerOf(claimId);

        // Record redemption on claim (validates vesting internally)
        CLAIM.recordRedemption(claimId, units, reasonHash);

        // Mint clean, unconditional stake
        uint256 stakeId = STAKE.mintStake(to, pactId, units, c.unitType);

        stakeIdByRedemptionId[redemptionId] = stakeId;
        stakeParamsHashByRedemptionId[redemptionId] = paramsHash;

        emit Redeemed(redemptionId, claimId, stakeId);
        return stakeId;
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
