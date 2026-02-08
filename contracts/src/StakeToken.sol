// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title StakeToken
 * @notice Post-transition ERC-20 token with authorized supply cap, per-address lockup,
 *         and governance exclusion for the protocol fee address.
 *
 * Design:
 *   - authorizedSupply is the hard cap. totalSupply MUST NOT exceed it.
 *   - Per-address lockup: locked addresses cannot transfer tokens except to whitelisted
 *     destinations (vault, governance contracts).
 *   - Protocol fee address is permanently excluded from governance voting weight.
 *   - Only the vault (MINTER_ROLE) can mint tokens.
 */
contract StakeToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    uint256 public authorizedSupply;
    address public immutable protocolFeeAddress;

    // Per-address lockup
    mapping(address => uint64) public lockUntil;

    // Whitelisted transfer destinations during lockup (vault, governance)
    mapping(address => bool) public lockupWhitelist;

    // Governance-excluded addresses (protocol fee address cannot vote)
    mapping(address => bool) public governanceExcluded;

    error ExceedsAuthorizedSupply();
    error TokensLocked();
    error InvalidSupply();
    error Unauthorized();

    event AuthorizedSupplyChanged(uint256 oldSupply, uint256 newSupply);
    event LockupSet(address indexed account, uint64 until);
    event LockupWhitelistUpdated(address indexed target, bool whitelisted);
    event GovernanceExclusionSet(address indexed account, bool excluded);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 authorizedSupply_,
        address vault_,
        address protocolFeeAddress_,
        address governance_
    )
        ERC20(name_, symbol_)
    {
        if (authorizedSupply_ == 0) revert InvalidSupply();

        authorizedSupply = authorizedSupply_;
        protocolFeeAddress = protocolFeeAddress_;

        _grantRole(DEFAULT_ADMIN_ROLE, governance_);
        _grantRole(MINTER_ROLE, vault_);
        _grantRole(GOVERNANCE_ROLE, governance_);

        // Vault and governance are whitelisted destinations during lockup
        lockupWhitelist[vault_] = true;
        lockupWhitelist[governance_] = true;

        // Protocol fee address is permanently excluded from governance
        governanceExcluded[protocolFeeAddress_] = true;

        emit GovernanceExclusionSet(protocolFeeAddress_, true);
        emit LockupWhitelistUpdated(vault_, true);
        emit LockupWhitelistUpdated(governance_, true);
    }

    /**
     * @notice Mint tokens. Only callable by vault (MINTER_ROLE).
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (totalSupply() + amount > authorizedSupply) revert ExceedsAuthorizedSupply();
        _mint(to, amount);
    }

    /**
     * @notice Set lockup for an address. Only callable by vault during transition.
     */
    function setLockup(address account, uint64 until) external onlyRole(MINTER_ROLE) {
        lockUntil[account] = until;
        emit LockupSet(account, until);
    }

    /**
     * @notice Increase the authorized supply. Requires GOVERNANCE_ROLE (supermajority vote).
     */
    function setAuthorizedSupply(uint256 newSupply) external onlyRole(GOVERNANCE_ROLE) {
        if (newSupply < totalSupply()) revert InvalidSupply();
        uint256 oldSupply = authorizedSupply;
        authorizedSupply = newSupply;
        emit AuthorizedSupplyChanged(oldSupply, newSupply);
    }

    /**
     * @notice Update lockup whitelist. Only callable by governance.
     */
    function setLockupWhitelist(address target, bool whitelisted) external onlyRole(GOVERNANCE_ROLE) {
        lockupWhitelist[target] = whitelisted;
        emit LockupWhitelistUpdated(target, whitelisted);
    }

    /**
     * @notice Check if an address is locked
     */
    function isLocked(address account) external view returns (bool) {
        return lockUntil[account] > block.timestamp;
    }

    /**
     * @notice Get governance-eligible balance (0 for excluded addresses)
     */
    function governanceBalance(address account) external view returns (uint256) {
        if (governanceExcluded[account]) return 0;
        return balanceOf(account);
    }

    /**
     * @dev Override _update to enforce lockup restrictions.
     *      Locked addresses can only transfer to whitelisted destinations.
     */
    function _update(address from, address to, uint256 amount) internal override {
        // Allow minting and burning unconditionally
        if (from != address(0) && to != address(0)) {
            // Check lockup
            if (lockUntil[from] > block.timestamp) {
                if (!lockupWhitelist[to]) revert TokensLocked();
            }
        }
        super._update(from, to, amount);
    }
}
