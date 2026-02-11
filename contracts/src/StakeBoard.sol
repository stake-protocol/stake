// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title StakeBoard
 * @notice Onchain board governance for Stake Protocol.
 *
 * The Board is designed to be set as the authority on a StakeCertificates contract.
 * Every material action that changes the cap table flows through the Board, creating
 * an authenticated, timestamped, immutable record of every board decision.
 *
 * Key properties:
 *   - Members sign with their wallets — no DocuSign, no signature hunting.
 *   - Non-responsive members are excluded from quorum after the response window.
 *   - A single founder is a board of one with quorum of one.
 *   - Every executed proposal is an onchain board resolution.
 *
 * The Board encodes four centuries of corporate governance into smart contracts:
 * a set of governors, a quorum threshold, and a response deadline.
 */
contract StakeBoard {
    // ============ State ============

    address public target; // The StakeCertificates contract this board governs

    address[] public members;
    mapping(address => bool) public isMember;
    uint256 public quorum; // minimum approvals needed (from responsive members)
    uint64 public responseWindow; // seconds members have to respond (default 7 days)

    struct Proposal {
        address proposer;
        bytes data; // calldata for the target contract
        string description; // human-readable description of the action
        uint64 createdAt;
        uint64 deadline; // createdAt + responseWindow
        uint256 approvalCount;
        bool executed;
        bool cancelled;
    }

    mapping(uint256 => Proposal) internal _proposals;
    mapping(uint256 => mapping(address => bool)) public hasApproved;
    mapping(uint256 => mapping(address => bool)) public hasResponded;
    mapping(uint256 => uint256) public responseCount;
    uint256 public proposalCount;

    // ============ Events ============

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        uint64 deadline
    );
    event ProposalApproved(uint256 indexed proposalId, address indexed member);
    event ProposalRejected(uint256 indexed proposalId, address indexed member);
    event ProposalExecuted(uint256 indexed proposalId, uint256 approvals, uint256 respondedMembers);
    event ProposalCancelled(uint256 indexed proposalId);
    event MemberAdded(address indexed member);
    event MemberRemoved(address indexed member);
    event QuorumUpdated(uint256 oldQuorum, uint256 newQuorum);
    event ResponseWindowUpdated(uint64 oldWindow, uint64 newWindow);

    // ============ Errors ============

    error NotMember();
    error NotBoard();
    error InvalidQuorum();
    error InvalidMember();
    error MemberAlreadyExists();
    error MemberNotFound();
    error ProposalNotFound();
    error ProposalAlreadyExecuted();
    error ProposalCancelledError();
    error ProposalExpiredWithoutQuorum();
    error DeadlineNotReached();
    error QuorumNotMet();
    error AlreadyResponded();
    error ExecutionFailed();
    error EmptyMembers();

    // ============ Modifiers ============

    modifier onlyMember() {
        if (!isMember[msg.sender]) revert NotMember();
        _;
    }

    modifier onlyBoard() {
        if (msg.sender != address(this)) revert NotBoard();
        _;
    }

    // ============ Constructor ============

    /**
     * @notice Deploy a new Board.
     * @param target_ The StakeCertificates contract this board governs.
     * @param members_ Initial board members (wallets).
     * @param quorum_ Minimum approvals needed.
     * @param responseWindow_ Seconds members have to respond (default: 7 days = 604800).
     */
    constructor(
        address target_,
        address[] memory members_,
        uint256 quorum_,
        uint64 responseWindow_
    ) {
        if (members_.length == 0) revert EmptyMembers();
        if (quorum_ == 0 || quorum_ > members_.length) revert InvalidQuorum();

        target = target_;
        quorum = quorum_;
        responseWindow = responseWindow_;

        for (uint256 i = 0; i < members_.length; i++) {
            if (members_[i] == address(0)) revert InvalidMember();
            if (isMember[members_[i]]) revert MemberAlreadyExists();
            isMember[members_[i]] = true;
            members.push(members_[i]);
            emit MemberAdded(members_[i]);
        }
    }

    // ============ Proposal Lifecycle ============

    /**
     * @notice Create a proposal for a board action.
     *         Any member can propose. The proposal includes the calldata to execute
     *         on the target contract if approved.
     * @param data The calldata to execute on the target contract.
     * @param description Human-readable description of the action.
     */
    function propose(
        bytes calldata data,
        string calldata description
    )
        external
        onlyMember
        returns (uint256 proposalId)
    {
        proposalId = proposalCount++;

        _proposals[proposalId] = Proposal({
            proposer: msg.sender,
            data: data,
            description: description,
            createdAt: uint64(block.timestamp),
            deadline: uint64(block.timestamp) + responseWindow,
            approvalCount: 1, // proposer auto-approves
            executed: false,
            cancelled: false
        });

        // Proposer has responded and approved
        hasApproved[proposalId][msg.sender] = true;
        hasResponded[proposalId][msg.sender] = true;
        responseCount[proposalId] = 1;

        emit ProposalCreated(proposalId, msg.sender, description, _proposals[proposalId].deadline);
        emit ProposalApproved(proposalId, msg.sender);
    }

    /**
     * @notice Approve a proposal. Members have until the deadline to respond.
     */
    function approve(uint256 proposalId) external onlyMember {
        Proposal storage p = _proposals[proposalId];
        if (p.createdAt == 0) revert ProposalNotFound();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (p.cancelled) revert ProposalCancelledError();
        if (hasResponded[proposalId][msg.sender]) revert AlreadyResponded();

        hasResponded[proposalId][msg.sender] = true;
        hasApproved[proposalId][msg.sender] = true;
        responseCount[proposalId]++;
        p.approvalCount++;

        emit ProposalApproved(proposalId, msg.sender);
    }

    /**
     * @notice Reject a proposal. Counts as a response but not an approval.
     */
    function reject(uint256 proposalId) external onlyMember {
        Proposal storage p = _proposals[proposalId];
        if (p.createdAt == 0) revert ProposalNotFound();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (p.cancelled) revert ProposalCancelledError();
        if (hasResponded[proposalId][msg.sender]) revert AlreadyResponded();

        hasResponded[proposalId][msg.sender] = true;
        responseCount[proposalId]++;

        emit ProposalRejected(proposalId, msg.sender);
    }

    /**
     * @notice Execute a proposal. Can be called by anyone once conditions are met.
     *
     * Execution logic:
     *   - Before deadline: requires approvalCount >= quorum (early execution if all needed approvals in).
     *   - After deadline: non-responsive members are excluded. Quorum is recalculated against
     *     responsive members only. If approvals >= adjusted quorum, proposal executes.
     *
     * This means checked-out board members cannot block the company. If they don't respond
     * within the window, the remaining members proceed by majority.
     */
    function execute(uint256 proposalId) external {
        Proposal storage p = _proposals[proposalId];
        if (p.createdAt == 0) revert ProposalNotFound();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (p.cancelled) revert ProposalCancelledError();

        uint256 approvals = p.approvalCount;
        uint256 responded = responseCount[proposalId];
        uint256 totalMembers = members.length;

        if (block.timestamp <= p.deadline) {
            // Before deadline: need full quorum from total members
            if (approvals < quorum) revert QuorumNotMet();
        } else {
            // After deadline: non-responsive members excluded
            // Adjusted quorum = ceil(quorum * responded / totalMembers)
            // But at minimum 1 approval required
            uint256 adjustedQuorum;
            if (responded == 0) {
                revert QuorumNotMet();
            } else if (responded >= totalMembers) {
                // Everyone responded — use normal quorum
                adjustedQuorum = quorum;
            } else {
                // Scale quorum proportionally to responsive members
                // Using ceiling division: (a + b - 1) / b
                adjustedQuorum = (quorum * responded + totalMembers - 1) / totalMembers;
                if (adjustedQuorum == 0) adjustedQuorum = 1;
            }

            if (approvals < adjustedQuorum) revert QuorumNotMet();
        }

        p.executed = true;

        // Execute the action on the target contract
        (bool success,) = target.call(p.data);
        if (!success) revert ExecutionFailed();

        emit ProposalExecuted(proposalId, approvals, responded);
    }

    /**
     * @notice Cancel a proposal. Only the proposer can cancel, and only before execution.
     */
    function cancel(uint256 proposalId) external {
        Proposal storage p = _proposals[proposalId];
        if (p.createdAt == 0) revert ProposalNotFound();
        if (p.executed) revert ProposalAlreadyExecuted();
        if (msg.sender != p.proposer) revert NotMember();

        p.cancelled = true;
        emit ProposalCancelled(proposalId);
    }

    // ============ Board Management (self-governed) ============

    /**
     * @notice Add a new board member. Must be called by the board itself (via proposal).
     */
    function addMember(address member) external onlyBoard {
        if (member == address(0)) revert InvalidMember();
        if (isMember[member]) revert MemberAlreadyExists();

        isMember[member] = true;
        members.push(member);
        emit MemberAdded(member);
    }

    /**
     * @notice Remove a board member. Must be called by the board itself (via proposal).
     *         Quorum is automatically adjusted down if it exceeds new member count.
     */
    function removeMember(address member) external onlyBoard {
        if (!isMember[member]) revert MemberNotFound();
        if (members.length <= 1) revert InvalidQuorum(); // can't remove last member

        isMember[member] = false;

        // Remove from array (swap and pop)
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == member) {
                members[i] = members[members.length - 1];
                members.pop();
                break;
            }
        }

        // Auto-adjust quorum if it exceeds new member count
        if (quorum > members.length) {
            uint256 oldQuorum = quorum;
            quorum = members.length;
            emit QuorumUpdated(oldQuorum, quorum);
        }

        emit MemberRemoved(member);
    }

    /**
     * @notice Update the quorum. Must be called by the board itself (via proposal).
     */
    function setQuorum(uint256 newQuorum) external onlyBoard {
        if (newQuorum == 0 || newQuorum > members.length) revert InvalidQuorum();
        uint256 oldQuorum = quorum;
        quorum = newQuorum;
        emit QuorumUpdated(oldQuorum, newQuorum);
    }

    /**
     * @notice Update the response window. Must be called by the board itself (via proposal).
     */
    function setResponseWindow(uint64 newWindow) external onlyBoard {
        uint64 oldWindow = responseWindow;
        responseWindow = newWindow;
        emit ResponseWindowUpdated(oldWindow, newWindow);
    }

    // ============ View Functions ============

    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address proposer,
            string memory description,
            uint64 createdAt,
            uint64 deadline,
            uint256 approvalCount,
            uint256 responded,
            bool executed,
            bool cancelled
        )
    {
        Proposal storage p = _proposals[proposalId];
        return (
            p.proposer,
            p.description,
            p.createdAt,
            p.deadline,
            p.approvalCount,
            responseCount[proposalId],
            p.executed,
            p.cancelled
        );
    }

    function getProposalData(uint256 proposalId) external view returns (bytes memory) {
        return _proposals[proposalId].data;
    }

    function memberCount() external view returns (uint256) {
        return members.length;
    }

    function getMember(uint256 index) external view returns (address) {
        return members[index];
    }

    function getAllMembers() external view returns (address[] memory) {
        return members;
    }
}
