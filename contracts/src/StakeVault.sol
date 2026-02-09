// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {StakeCertificates, SoulboundStake, SoulboundClaim, StakeState, ClaimState} from "./StakeCertificates.sol";
import {StakeToken} from "./StakeToken.sol";
import {ProtocolFeeLiquidator} from "./ProtocolFeeLiquidator.sol";

/**
 * @title StakeVault
 * @notice Post-transition contract that custodies certificates, mints tokens, manages
 *         governance seats, and enforces the protocol fee.
 *
 * Lifecycle:
 *   1. Vault is deployed with references to StakeCertificates and StakeToken.
 *   2. Issuer calls StakeCertificates.initiateTransition(vault) — sets vault on certs.
 *   3. Vault.processTransitionBatch() — transfers certs to vault, mints tokens.
 *   4. Holders call claimTokens() after lockup to withdraw.
 *   5. Governance seats become available for auction.
 */
contract StakeVault is AccessControl, ReentrancyGuard {
    // ============ Roles ============
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ============ Protocol Constants ============
    uint16 public constant PROTOCOL_FEE_BPS = 100; // 1% of minted supply
    uint16 public constant BPS_BASE = 10_000;

    // ============ Core References ============
    StakeCertificates public immutable certificates;
    SoulboundStake public immutable stakeContract;
    StakeToken public immutable token;

    // ============ Transition State ============
    bool public transitionProcessed;
    uint64 public transitionTimestamp;

    // ============ Configuration ============
    uint64 public lockupDuration; // default 90 days
    uint32 public governanceTermDays; // default 365
    uint16 public auctionMinBidBps; // default 1000 (10%)
    uint16 public overrideThresholdBps; // default 5001 (50%+1)
    uint16 public overrideQuorumBps; // default 2000 (20%)

    // ============ Protocol Fee ============
    address public protocolFeeAddress;
    ProtocolFeeLiquidator public protocolFeeLiquidator;
    uint256 public protocolFeeBalance; // accumulated fee tokens not yet sent to liquidator

    // ============ Certificate Tracking ============
    struct DepositedCert {
        address originalHolder;
        uint256 vestedUnitsAtTransition;
        uint256 totalUnits;
        uint64 vestStart;
        uint64 vestCliff;
        uint64 vestEnd;
        bool tokensFullyClaimed;
        uint256 tokensClaimed;
    }

    mapping(uint256 => DepositedCert) public depositedStakes;
    uint256[] public depositedStakeIds;

    // ============ Token Claiming ============
    mapping(address => uint256) public totalTokensAllocated;
    mapping(address => uint256) public tokensClaimed;
    mapping(address => uint64) public holderLockupEnd;

    // ============ Governance Seats ============
    struct GovernanceSeat {
        address governor;
        uint64 termStart;
        uint64 termEnd;
        uint256 bidAmount;
        bool active;
    }

    mapping(uint256 => GovernanceSeat) public seats;
    uint256 public totalGovernanceWeight;

    // ============ Governance Seat Auctions ============
    struct Auction {
        uint256 certId;
        uint64 startTime;
        uint64 endTime;
        address highestBidder;
        uint256 highestBid;
        bool settled;
    }

    mapping(uint256 => Auction) public auctions;
    uint256 public auctionDuration; // default 7 days

    // ============ Override ============
    struct OverrideProposal {
        uint64 proposedAt;
        uint64 votingEnd;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    uint256 public overrideProposalCount;
    mapping(uint256 => OverrideProposal) internal _overrideProposals;
    uint64 public lastOverrideTime;
    uint64 public constant OVERRIDE_COOLDOWN = 90 days;
    uint64 public constant OVERRIDE_VOTING_PERIOD = 14 days;

    // ============ Events ============
    event TransitionBatchProcessed(uint256 stakesProcessed, uint256 totalTokensMinted);
    event TokensClaimed(address indexed holder, uint256 amount);
    event GovernanceSeatAuctionStarted(uint256 indexed certId, uint64 startTime, uint64 endTime);
    event GovernanceSeatBid(uint256 indexed certId, address indexed bidder, uint256 amount);
    event GovernanceSeatAwarded(uint256 indexed certId, address indexed governor, uint256 bidAmount, uint64 termEnd);
    event GovernanceSeatReclaimed(uint256 indexed certId, address indexed formerGovernor);
    event OverrideProposed(uint256 indexed proposalId, address indexed proposer);
    event OverrideVoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event OverrideExecuted(uint256 indexed proposalId);
    event ProtocolFeeLiquidatorDeployed(address indexed liquidator, uint256 feeTokens);

    // ============ Errors ============
    error TransitionNotInitiated();
    error TransitionAlreadyProcessed();
    error NoTokensToClaim();
    error LockupActive();
    error AuctionAlreadyActive();
    error AuctionNotActive();
    error BidTooLow();
    error AuctionNotEnded();
    error SeatStillActive();
    error CertNotInVault();
    error SeatNotActive();
    error OverrideCooldownActive();
    error VotingPeriodClosed();
    error VotingPeriodNotEnded();
    error OverrideQuorumNotMet();
    error OverrideThresholdNotMet();
    error AlreadyVoted();
    error InvalidProposal();
    error Unauthorized();
    error AlreadyDeposited();

    constructor(
        address certificates_,
        address token_,
        address protocolFeeAddress_,
        address operator_,
        uint64 lockupDuration_,
        uint32 governanceTermDays_,
        uint16 auctionMinBidBps_,
        uint16 overrideThresholdBps_,
        uint16 overrideQuorumBps_,
        uint64 auctionDuration_
    ) {
        certificates = StakeCertificates(certificates_);
        stakeContract = certificates.STAKE();
        token = StakeToken(token_);
        protocolFeeAddress = protocolFeeAddress_;

        lockupDuration = lockupDuration_;
        governanceTermDays = governanceTermDays_;
        auctionMinBidBps = auctionMinBidBps_;
        overrideThresholdBps = overrideThresholdBps_;
        overrideQuorumBps = overrideQuorumBps_;
        auctionDuration = auctionDuration_;

        _grantRole(DEFAULT_ADMIN_ROLE, operator_);
        _grantRole(OPERATOR_ROLE, operator_);
    }

    // ============ Transition ============

    /**
     * @notice Process transition: transfer stakes to vault and mint tokens.
     *         Protocol fees accumulate in the vault — call deployLiquidator() after all
     *         batches are processed to deploy the fee liquidator with all fee tokens.
     * @param stakeIds Array of stake token IDs to process.
     */
    function processTransitionBatch(
        uint256[] calldata stakeIds
    )
        external
        onlyRole(OPERATOR_ROLE)
        nonReentrant
    {
        if (!certificates.transitioned()) revert TransitionNotInitiated();

        if (!transitionProcessed) {
            transitionTimestamp = uint64(block.timestamp);
            transitionProcessed = true;
        }

        uint256 totalMinted;
        uint64 lockupEnd = uint64(block.timestamp) + lockupDuration;

        for (uint256 i; i < stakeIds.length; i++) {
            uint256 stakeId = stakeIds[i];

            // Prevent duplicate processing — each stakeId can only be deposited once
            if (depositedStakes[stakeId].originalHolder != address(0)) revert AlreadyDeposited();

            address holder = stakeContract.ownerOf(stakeId);
            StakeState memory s = stakeContract.getStake(stakeId);

            // Transfer cert to vault (vault is authorized in _update hook)
            stakeContract.transferFrom(holder, address(this), stakeId);

            // Calculate vested units at transition
            uint256 vestedNow = s.revoked ? s.units : _calculateVested(s);

            depositedStakes[stakeId] = DepositedCert({
                originalHolder: holder,
                vestedUnitsAtTransition: vestedNow,
                totalUnits: s.units,
                vestStart: s.vestStart,
                vestCliff: s.vestCliff,
                vestEnd: s.vestEnd,
                tokensFullyClaimed: false,
                tokensClaimed: 0
            });
            depositedStakeIds.push(stakeId);

            // Mint tokens for vested units
            if (vestedNow > 0) {
                token.mint(address(this), vestedNow);
                totalTokensAllocated[holder] += vestedNow;
                totalMinted += vestedNow;
            }

            // Set lockup for holder
            if (holderLockupEnd[holder] == 0) {
                holderLockupEnd[holder] = lockupEnd;
                token.setLockup(holder, lockupEnd);
            }
        }

        // Mint protocol fee (1% of this batch's minted tokens)
        // Fees always accumulate in the vault until deployLiquidator is called.
        // This prevents stranding tokens in a liquidator whose totalTokens was
        // already initialized from an earlier batch.
        if (totalMinted > 0) {
            uint256 protocolFee = (totalMinted * PROTOCOL_FEE_BPS) / BPS_BASE;
            if (protocolFee > 0) {
                token.mint(address(this), protocolFee);
                protocolFeeBalance += protocolFee;
            }
        }

        emit TransitionBatchProcessed(stakeIds.length, totalMinted);
    }

    /**
     * @notice Deploy the protocol fee liquidator. Can be called separately if not done during transition.
     */
    function deployLiquidator(address liquidationRouter) external onlyRole(OPERATOR_ROLE) {
        if (address(protocolFeeLiquidator) != address(0)) revert TransitionAlreadyProcessed();
        if (protocolFeeBalance == 0) revert NoTokensToClaim();
        uint256 feeTokens = protocolFeeBalance;
        protocolFeeBalance = 0;
        _deployLiquidator(feeTokens, liquidationRouter);
    }

    function _deployLiquidator(uint256 feeTokens, address liquidationRouter) internal {
        protocolFeeLiquidator = new ProtocolFeeLiquidator(
            address(token),
            liquidationRouter,
            protocolFeeAddress,
            uint64(block.timestamp) + lockupDuration, // Same lockup as everyone: 90 days
            365 days // 12-month linear sell
        );

        token.transfer(address(protocolFeeLiquidator), feeTokens);
        protocolFeeLiquidator.initialize();
        emit ProtocolFeeLiquidatorDeployed(address(protocolFeeLiquidator), feeTokens);
    }

    // ============ Token Claiming ============

    /**
     * @notice Claim available (vested + unlocked) tokens.
     */
    function claimTokens() external nonReentrant {
        uint64 lockupEnd = holderLockupEnd[msg.sender];
        if (block.timestamp < lockupEnd) revert LockupActive();

        uint256 allocated = totalTokensAllocated[msg.sender];
        uint256 claimed = tokensClaimed[msg.sender];
        uint256 available = allocated - claimed;

        if (available == 0) revert NoTokensToClaim();

        tokensClaimed[msg.sender] = allocated;
        token.transfer(msg.sender, available);

        emit TokensClaimed(msg.sender, available);
    }

    /**
     * @notice Release newly vested tokens for a specific stake (callable by anyone).
     */
    function releaseVestedTokens(uint256 stakeId) external nonReentrant {
        DepositedCert storage cert = depositedStakes[stakeId];
        if (cert.originalHolder == address(0)) revert TransitionNotInitiated();
        if (cert.tokensFullyClaimed) return;

        uint256 totalVestedNow;
        if (block.timestamp >= cert.vestEnd) {
            totalVestedNow = cert.totalUnits;
        } else if (block.timestamp < cert.vestCliff) {
            totalVestedNow = cert.vestedUnitsAtTransition;
        } else {
            uint256 elapsed = block.timestamp - cert.vestStart;
            uint256 duration = cert.vestEnd - cert.vestStart;
            totalVestedNow = duration == 0 ? cert.totalUnits : (cert.totalUnits * elapsed) / duration;
        }

        uint256 newlyVested = totalVestedNow - cert.vestedUnitsAtTransition - cert.tokensClaimed;
        if (newlyVested == 0) return;

        cert.tokensClaimed += newlyVested;
        if (cert.vestedUnitsAtTransition + cert.tokensClaimed >= cert.totalUnits) cert.tokensFullyClaimed = true;

        // Mint newly vested tokens and allocate to holder
        token.mint(address(this), newlyVested);
        totalTokensAllocated[cert.originalHolder] += newlyVested;
    }

    // ============ Governance Seats ============

    /**
     * @notice Start an auction for a governance seat.
     */
    function startSeatAuction(uint256 certId) external {
        // Cert must be in the vault and not currently governed
        if (stakeContract.ownerOf(certId) != address(this)) revert CertNotInVault();
        GovernanceSeat storage seat = seats[certId];
        if (seat.active) revert SeatStillActive();

        Auction storage a = auctions[certId];
        if (a.startTime != 0 && !a.settled) revert AuctionAlreadyActive();

        uint64 start = uint64(block.timestamp);
        uint64 end = start + uint64(auctionDuration);

        auctions[certId] = Auction({
            certId: certId, startTime: start, endTime: end, highestBidder: address(0), highestBid: 0, settled: false
        });

        emit GovernanceSeatAuctionStarted(certId, start, end);
    }

    /**
     * @notice Bid on a governance seat. Tokens are deposited.
     */
    function bidForSeat(uint256 certId, uint256 amount) external nonReentrant {
        Auction storage a = auctions[certId];
        if (a.startTime == 0 || a.settled) revert AuctionNotActive();
        if (block.timestamp > a.endTime) revert AuctionNotActive();

        // Enforce minimum bid
        StakeState memory s = stakeContract.getStake(certId);
        uint256 minBid = (s.units * auctionMinBidBps) / BPS_BASE;
        if (amount < minBid) revert BidTooLow();
        if (amount <= a.highestBid) revert BidTooLow();

        // Return previous bidder's tokens
        if (a.highestBidder != address(0)) token.transfer(a.highestBidder, a.highestBid);

        // Take new bidder's tokens
        token.transferFrom(msg.sender, address(this), amount);

        a.highestBidder = msg.sender;
        a.highestBid = amount;

        emit GovernanceSeatBid(certId, msg.sender, amount);
    }

    /**
     * @notice Settle auction and award governance seat to winner.
     */
    function settleAuction(uint256 certId) external nonReentrant {
        Auction storage a = auctions[certId];
        if (a.startTime == 0 || a.settled) revert AuctionNotActive();
        if (block.timestamp <= a.endTime) revert AuctionNotEnded();

        a.settled = true;

        if (a.highestBidder == address(0)) {
            // No bids — seat stays in vault
            return;
        }

        uint64 termEnd = uint64(block.timestamp) + uint64(governanceTermDays) * 1 days;

        seats[certId] = GovernanceSeat({
            governor: a.highestBidder,
            termStart: uint64(block.timestamp),
            termEnd: termEnd,
            bidAmount: a.highestBid,
            active: true
        });

        // Transfer cert to governor (vault-initiated, bypasses soulbound)
        stakeContract.transferFrom(address(this), a.highestBidder, certId);

        StakeState memory s = stakeContract.getStake(certId);
        totalGovernanceWeight += s.units;

        emit GovernanceSeatAwarded(certId, a.highestBidder, a.highestBid, termEnd);
    }

    /**
     * @notice Reclaim a governance seat after term expiry. Permissionless.
     */
    function reclaimSeat(uint256 certId) external nonReentrant {
        GovernanceSeat storage seat = seats[certId];
        if (!seat.active) revert SeatNotActive();
        if (block.timestamp < seat.termEnd) revert SeatStillActive();

        address formerGovernor = seat.governor;
        uint256 bidReturn = seat.bidAmount;

        // Force-transfer cert back to vault
        stakeContract.transferFrom(formerGovernor, address(this), certId);

        StakeState memory s = stakeContract.getStake(certId);
        totalGovernanceWeight -= s.units;

        // Return bid tokens
        if (bidReturn > 0) token.transfer(formerGovernor, bidReturn);

        seat.active = false;
        seat.governor = address(0);

        emit GovernanceSeatReclaimed(certId, formerGovernor);
    }

    // ============ Override ============

    /**
     * @notice Propose a token holder override (nuclear option).
     */
    function proposeOverride() external returns (uint256 proposalId) {
        if (block.timestamp < lastOverrideTime + OVERRIDE_COOLDOWN) revert OverrideCooldownActive();
        if (token.governanceBalance(msg.sender) == 0) revert Unauthorized();

        proposalId = overrideProposalCount++;
        OverrideProposal storage p = _overrideProposals[proposalId];
        p.proposedAt = uint64(block.timestamp);
        p.votingEnd = uint64(block.timestamp) + OVERRIDE_VOTING_PERIOD;

        emit OverrideProposed(proposalId, msg.sender);
    }

    /**
     * @notice Vote on an override proposal.
     */
    function voteOverride(uint256 proposalId, bool support) external {
        if (proposalId >= overrideProposalCount) revert InvalidProposal();
        OverrideProposal storage p = _overrideProposals[proposalId];
        if (block.timestamp > p.votingEnd) revert VotingPeriodClosed();
        if (p.hasVoted[msg.sender]) revert AlreadyVoted();

        uint256 weight = token.governanceBalance(msg.sender);
        if (weight == 0) revert Unauthorized();

        p.hasVoted[msg.sender] = true;

        if (support) p.votesFor += weight;
        else p.votesAgainst += weight;

        emit OverrideVoteCast(proposalId, msg.sender, support, weight);
    }

    /**
     * @notice Execute a passed override: remove all governors, return all seats to vault.
     */
    function executeOverride(uint256 proposalId) external nonReentrant {
        if (proposalId >= overrideProposalCount) revert InvalidProposal();
        OverrideProposal storage p = _overrideProposals[proposalId];
        if (block.timestamp <= p.votingEnd) revert VotingPeriodNotEnded();
        if (p.executed) revert InvalidProposal();

        // Check quorum
        uint256 totalVotes = p.votesFor + p.votesAgainst;
        uint256 quorumRequired = (token.totalSupply() * overrideQuorumBps) / BPS_BASE;
        if (totalVotes < quorumRequired) revert OverrideQuorumNotMet();

        // Check threshold
        uint256 thresholdRequired = (totalVotes * overrideThresholdBps) / BPS_BASE;
        if (p.votesFor < thresholdRequired) revert OverrideThresholdNotMet();

        p.executed = true;
        lastOverrideTime = uint64(block.timestamp);

        // Remove all active governors
        for (uint256 i; i < depositedStakeIds.length; i++) {
            uint256 certId = depositedStakeIds[i];
            GovernanceSeat storage seat = seats[certId];
            if (seat.active) {
                address formerGovernor = seat.governor;

                // Force-transfer cert back
                stakeContract.transferFrom(formerGovernor, address(this), certId);

                // Return bid
                if (seat.bidAmount > 0) token.transfer(formerGovernor, seat.bidAmount);

                seat.active = false;
                seat.governor = address(0);

                emit GovernanceSeatReclaimed(certId, formerGovernor);
            }
        }
        totalGovernanceWeight = 0;

        emit OverrideExecuted(proposalId);
    }

    // ============ View Functions ============

    function getGovernor(uint256 certId)
        external
        view
        returns (address governor, uint64 termStart, uint64 termEnd, uint256 bidAmount)
    {
        GovernanceSeat storage seat = seats[certId];
        return (seat.governor, seat.termStart, seat.termEnd, seat.bidAmount);
    }

    function isGovernanceSeat(uint256 certId) external view returns (bool) {
        return seats[certId].active;
    }

    function depositedStakeCount() external view returns (uint256) {
        return depositedStakeIds.length;
    }

    // ============ Internal ============

    function _calculateVested(StakeState memory s) internal view returns (uint256) {
        if (block.timestamp < s.vestCliff) return 0;
        if (block.timestamp >= s.vestEnd) return s.units;

        uint256 elapsed = block.timestamp - s.vestStart;
        uint256 duration = s.vestEnd - s.vestStart;
        if (duration == 0) return s.units;

        return (s.units * elapsed) / duration;
    }

    /**
     * @dev Required to receive ERC-721 tokens via safeTransferFrom
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
