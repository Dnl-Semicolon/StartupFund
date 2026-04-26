// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./ICampaign.sol";
import "./IVerification.sol";

/// @title CampaignVoting - Community approval gate for new campaigns
/// @notice Every new campaign enters PENDING status. Registered wallets have a
///         voting window (default 72 hours) to cast Approve or Disapprove. After
///         the window, anyone may call settleVoting() to transition the campaign:
///
///           - zero votes           → auto-activate (prevents empty-platform deadlock)
///           - quorum met + ≥70% approve → activate
///           - otherwise            → reject
///
/// @dev For class-demo convenience, the owner can shorten the window (e.g. 120s)
///      and quorum (e.g. 2) via setVotingWindow / setQuorum. Real-world defaults
///      stay visible in source so the "we purposefully lowered for demo" story
///      is self-evident.
contract CampaignVoting {

    ICampaign     public immutable campaignManager;
    IVerification public immutable accessControl;

    address public owner;
    address public authorized;    // StartupFund — sole caller allowed to open voting

    uint256 public votingWindowSeconds = 72 hours;  // 259,200s
    uint256 public quorumRequired      = 10;

    // campaignId → timestamp when voting opened (0 = not opened yet)
    mapping(uint256 => uint256) public voteOpenTime;

    mapping(uint256 => uint256) public approveCount;
    mapping(uint256 => uint256) public disapproveCount;

    // campaignId → voter → voted?
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    // campaignId → voter → true=approve, false=disapprove
    mapping(uint256 => mapping(address => bool)) public voteChoice;

    // campaignId → has settleVoting() been called already?
    mapping(uint256 => bool) public settled;

    // Total votes a wallet has cast across all campaigns — for profile / leaderboard
    mapping(address => uint256) public walletVoteCount;

    // ─────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────

    event VotingOpened(uint256 indexed campaignId, uint256 windowEnd);
    event Voted(uint256 indexed campaignId, address indexed voter, bool approve);
    event CampaignApproved(uint256 indexed campaignId, uint256 approveVotes, uint256 totalVotes);
    event CampaignDeclined(uint256 indexed campaignId, uint256 approveVotes, uint256 totalVotes);
    event VotingWindowChanged(uint256 newSeconds);
    event QuorumChanged(uint256 newQuorum);

    // ─────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "CampaignVoting: Not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == authorized, "CampaignVoting: Not authorized");
        _;
    }

    // ─────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────

    constructor(address _campaignManager, address _accessControl) {
        require(_campaignManager != address(0), "CampaignVoting: Zero address");
        require(_accessControl  != address(0), "CampaignVoting: Zero address");
        owner           = msg.sender;
        campaignManager = ICampaign(_campaignManager);
        accessControl   = IVerification(_accessControl);
    }

    /// @notice Set the StartupFund address that is allowed to call openVoting().
    ///         Call once after StartupFund is deployed.
    function setAuthorized(address _authorized) external onlyOwner {
        require(_authorized != address(0), "CampaignVoting: Zero address");
        authorized = _authorized;
    }

    // ─────────────────────────────────────────────────────────────
    // Owner configuration (demo shortcuts)
    // ─────────────────────────────────────────────────────────────

    /// @notice Set how many seconds the voting window lasts. Demo: 120 (2 min).
    function setVotingWindow(uint256 seconds_) external onlyOwner {
        require(seconds_ >= 60, "CampaignVoting: Window too short");
        votingWindowSeconds = seconds_;
        emit VotingWindowChanged(seconds_);
    }

    /// @notice Set the minimum total votes required for a non-zero-vote decision
    ///         to be considered valid. Demo: 2. Real-world default: 10.
    function setQuorum(uint256 quorum) external onlyOwner {
        require(quorum >= 1, "CampaignVoting: Quorum must be >= 1");
        quorumRequired = quorum;
        emit QuorumChanged(quorum);
    }

    // ─────────────────────────────────────────────────────────────
    // Opened by StartupFund immediately after createCampaign
    // ─────────────────────────────────────────────────────────────

    /// @notice Open the voting window for a freshly-created campaign.
    ///         Called by StartupFund.createCampaign() right after the campaign
    ///         is minted in CampaignManager.
    function openVoting(uint256 campaignId) external onlyAuthorized {
        require(voteOpenTime[campaignId] == 0, "CampaignVoting: Already opened");
        voteOpenTime[campaignId] = block.timestamp;
        emit VotingOpened(campaignId, block.timestamp + votingWindowSeconds);
    }

    // ─────────────────────────────────────────────────────────────
    // Voting
    // ─────────────────────────────────────────────────────────────

    /// @notice Cast a vote on a PENDING campaign.
    /// @param campaignId  Target campaign
    /// @param approve     true = approve, false = disapprove
    /// @dev Creators cannot vote on their own campaigns (anti-self-promotion).
    function vote(uint256 campaignId, bool approve) external {
        require(accessControl.isRegistered(msg.sender), "CampaignVoting: Not registered");
        require(!accessControl.isBlocked(msg.sender),   "CampaignVoting: Wallet blocked");

        // Block self-voting — creator must rely on community
        (address creator, , , , , ) = campaignManager.getCampaignCore(campaignId);
        require(msg.sender != creator, "CampaignVoting: Creator cannot vote on own campaign");

        uint256 openTime = voteOpenTime[campaignId];
        require(openTime > 0,                                         "CampaignVoting: Voting not open");
        require(block.timestamp < openTime + votingWindowSeconds,     "CampaignVoting: Window closed");
        require(!settled[campaignId],                                 "CampaignVoting: Already settled");
        require(!hasVoted[campaignId][msg.sender],                    "CampaignVoting: Already voted");

        hasVoted[campaignId][msg.sender]   = true;
        voteChoice[campaignId][msg.sender] = approve;
        walletVoteCount[msg.sender]++;

        if (approve) {
            approveCount[campaignId]++;
        } else {
            disapproveCount[campaignId]++;
        }

        emit Voted(campaignId, msg.sender, approve);
    }

    // ─────────────────────────────────────────────────────────────
    // Settlement
    // ─────────────────────────────────────────────────────────────

    /// @notice Finalize voting once the window has closed. Callable by anyone.
    ///         Decision tree:
    ///           - total >= quorum AND approve*100/total >= 70     → activate
    ///           - otherwise (including 0 votes / below quorum)    → reject
    function settleVoting(uint256 campaignId) external {
        uint256 openTime = voteOpenTime[campaignId];
        require(openTime > 0,                                         "CampaignVoting: Voting not open");
        require(block.timestamp >= openTime + votingWindowSeconds,    "CampaignVoting: Window still open");
        require(!settled[campaignId],                                 "CampaignVoting: Already settled");

        settled[campaignId] = true;

        uint256 approves = approveCount[campaignId];
        uint256 total    = approves + disapproveCount[campaignId];

        // No special-case for zero votes: a campaign that fails to attract
        // community attention is treated the same as one that loses the vote.
        // Quorum gate must be met for any approval to count.
        bool passes = total >= quorumRequired && approves * 100 / total >= 70;

        if (passes) {
            campaignManager.activateCampaign(campaignId);
            emit CampaignApproved(campaignId, approves, total);
        } else {
            campaignManager.rejectCampaign(campaignId);
            emit CampaignDeclined(campaignId, approves, total);
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Read helpers
    // ─────────────────────────────────────────────────────────────

    /// @notice Full voting state for a campaign.
    function getVoteStatus(uint256 campaignId)
        external view
        returns (
            uint256 approves,
            uint256 disapproves,
            uint256 windowEnd,
            bool    isSettled
        )
    {
        uint256 openTime = voteOpenTime[campaignId];
        return (
            approveCount[campaignId],
            disapproveCount[campaignId],
            openTime == 0 ? 0 : openTime + votingWindowSeconds,
            settled[campaignId]
        );
    }

    /// @notice Seconds left in the voting window. 0 if closed or not opened.
    function timeRemaining(uint256 campaignId) external view returns (uint256) {
        uint256 openTime = voteOpenTime[campaignId];
        if (openTime == 0) return 0;
        uint256 end = openTime + votingWindowSeconds;
        return block.timestamp >= end ? 0 : end - block.timestamp;
    }
}
