// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./ICampaign.sol";

/// @title CampaignManager - Campaign creation, metadata storage, and status transitions
/// @notice Implements ICampaign. Does NOT hold any ETH — purely data management.
///         Only the StartupFund orchestrator (authorized address) can update campaign state.
/// @dev Campaign data is stored in a mapping. Milestones are added separately to avoid
///      passing complex tuple arrays in the initial create call.
contract CampaignManager is ICampaign {

    // ─────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────

    enum CampaignStatus { PENDING, ACTIVE, FUNDED, CANCELLED, REJECTED }

    struct Milestone {
        string title;
        string description;
        uint256 targetAmount; // in wei
        bool isReached;
    }

    struct Campaign {
        uint256 id;
        address creator;
        string title;
        string slug;
        string description;
        string shortDescription;
        string imageUrl;       // HTTPS URL or IPFS hash (e.g. "ipfs://Qm...")
        string category;       // "Tech" | "AI" | "Web3" | "Fintech" | "Healthcare" | "Green Energy"
        uint256 goalAmount;    // in wei
        uint256 raisedAmount;  // in wei, updated by StartupFund after each contribution
        uint256 minContribution; // in wei, minimum 1e15 (0.001 ETH)
        uint256 deadline;      // Unix timestamp
        CampaignStatus status;
        uint256 backersCount;
        string[] tags;         // searchable labels e.g. ["ai", "climate", "hardware"]
        Milestone[] milestones;
        // Profit-return fields (optional; both 0 = no profit-return offered)
        uint256 profitReturnRate;     // percent (0-100). 50 = creator promises 1.5x payout.
        uint256 profitReturnDeadline; // Unix timestamp. Must be > deadline.
    }

    // ─────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────

    mapping(uint256 => Campaign) private _campaigns;
    uint256 public override campaignCount;

    address public owner;
    address public authorized;      // StartupFund orchestrator
    address public votingContract;  // CampaignVoting — sole caller of activate/reject

    // ─────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 goalAmount,
        uint256 deadline
    );
    event CampaignFunded(uint256 indexed campaignId, uint256 totalRaised);
    event CampaignCancelled(uint256 indexed campaignId);
    event CampaignActivated(uint256 indexed campaignId);
    event CampaignRejected(uint256 indexed campaignId);
    event MilestoneAdded(uint256 indexed campaignId, uint256 milestoneIndex);
    event MilestoneReached(uint256 indexed campaignId, uint256 milestoneIndex);

    // ─────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "CampaignManager: Not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == authorized, "CampaignManager: Not authorized");
        _;
    }

    modifier onlyVoting() {
        require(msg.sender == votingContract, "CampaignManager: Not voting contract");
        _;
    }

    modifier campaignExists(uint256 campaignId) {
        require(campaignId < campaignCount, "CampaignManager: Campaign does not exist");
        _;
    }

    // ─────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    /// @notice Set the StartupFund orchestrator address. Call once after deploying StartupFund.
    function setAuthorized(address _authorized) external onlyOwner {
        require(_authorized != address(0), "CampaignManager: Zero address");
        authorized = _authorized;
    }

    /// @notice Set the CampaignVoting contract address. Call once after deploying CampaignVoting.
    ///         Only this contract can call activateCampaign/rejectCampaign.
    function setVotingContract(address _votingContract) external onlyOwner {
        require(_votingContract != address(0), "CampaignManager: Zero address");
        votingContract = _votingContract;
    }

    // ─────────────────────────────────────────────────────────────
    // Campaign Creation
    // ─────────────────────────────────────────────────────────────

    /// @notice Create a new campaign. Called by StartupFund (which validates the caller is registered).
    /// @param title         Campaign/startup name
    /// @param slug          URL-friendly identifier (e.g. "ecoflow-smart-grid")
    /// @param description   Full business plan (>= 100 chars recommended)
    /// @param shortDescription  Elevator pitch (20-160 chars)
    /// @param imageUrl      HTTPS URL or IPFS hash for cover image
    /// @param category      One of: Tech, Fintech, Healthcare, Green Energy, AI, Web3
    /// @param goalAmount    Funding target in wei (must be > 0)
    /// @param minContribution Minimum ETH per contribution in wei (>= 1e15 = 0.001 ETH)
    /// @param deadline      Unix timestamp for campaign end (any future time, max 60 days from now)
    /// @param tags          Searchable labels, lowercased by convention (e.g. ["ai", "climate"])
    /// @return campaignId   ID of the newly created campaign (0-indexed)
    /// @dev Campaign enters PENDING status. CampaignVoting.settleVoting() must be called
    ///      after the voting window closes to transition it to ACTIVE or REJECTED.
    function createCampaign(
        string memory title,
        string memory slug,
        string memory description,
        string memory shortDescription,
        string memory imageUrl,
        string memory category,
        uint256 goalAmount,
        uint256 minContribution,
        uint256 deadline,
        string[] memory tags
    ) external override onlyAuthorized returns (uint256 campaignId) {
        // Validations per assignment business rules
        require(goalAmount > 0, "CampaignManager: Goal must be > 0");
        require(
            deadline > block.timestamp,
            "CampaignManager: Deadline must be in the future"
        );
        require(
            deadline <= block.timestamp + 60 days,
            "CampaignManager: Deadline cannot exceed 60 days"
        );
        require(
            minContribution >= 1e15,
            "CampaignManager: Min contribution must be >= 0.001 ETH"
        );
        require(bytes(title).length > 0, "CampaignManager: Title required");

        campaignId = campaignCount;

        Campaign storage c = _campaigns[campaignId];
        c.id = campaignId;
        c.creator = tx.origin; // The user's wallet, not StartupFund contract
        c.title = title;
        c.slug = slug;
        c.description = description;
        c.shortDescription = shortDescription;
        c.imageUrl = imageUrl;
        c.category = category;
        c.goalAmount = goalAmount;
        c.raisedAmount = 0;
        c.minContribution = minContribution;
        c.deadline = deadline;
        c.status = CampaignStatus.PENDING;
        c.backersCount = 0;

        // Store tags (lowercased client-side by convention)
        for (uint256 i = 0; i < tags.length; i++) {
            c.tags.push(tags[i]);
        }
        // milestones[] starts empty; use addMilestone() to add them after activation

        campaignCount++;

        emit CampaignCreated(campaignId, c.creator, goalAmount, deadline);
    }

    // ─────────────────────────────────────────────────────────────
    // Voting-driven state transitions (called by CampaignVoting only)
    // ─────────────────────────────────────────────────────────────

    /// @notice Flip a PENDING campaign to ACTIVE. Called by CampaignVoting after approval.
    function activateCampaign(uint256 campaignId)
        external
        override
        onlyVoting
        campaignExists(campaignId)
    {
        Campaign storage c = _campaigns[campaignId];
        require(c.status == CampaignStatus.PENDING, "CampaignManager: Not pending");
        c.status = CampaignStatus.ACTIVE;
        emit CampaignActivated(campaignId);
    }

    /// @notice Flip a PENDING campaign to REJECTED. Called by CampaignVoting after disapproval.
    function rejectCampaign(uint256 campaignId)
        external
        override
        onlyVoting
        campaignExists(campaignId)
    {
        Campaign storage c = _campaigns[campaignId];
        require(c.status == CampaignStatus.PENDING, "CampaignManager: Not pending");
        c.status = CampaignStatus.REJECTED;
        emit CampaignRejected(campaignId);
    }

    /// @notice Force-cancel an ACTIVE campaign (e.g. community-flagged).
    ///         Called by StartupFund's flag handler when the threshold is hit.
    function forceCancelCampaign(uint256 campaignId)
        external
        onlyAuthorized
        campaignExists(campaignId)
    {
        Campaign storage c = _campaigns[campaignId];
        require(c.status == CampaignStatus.ACTIVE, "CampaignManager: Not active");
        c.status = CampaignStatus.CANCELLED;
        emit CampaignCancelled(campaignId);
    }

    // ─────────────────────────────────────────────────────────────
    // Milestone Management
    // ─────────────────────────────────────────────────────────────

    /// @notice Add a milestone to an ACTIVE campaign. Only the campaign creator can call.
    /// @param campaignId    Target campaign
    /// @param title         Milestone title
    /// @param description   What this milestone represents
    /// @param targetAmount  ETH amount (in wei) that marks this milestone
    function addMilestone(
        uint256 campaignId,
        string memory title,
        string memory description,
        uint256 targetAmount
    ) external campaignExists(campaignId) {
        Campaign storage c = _campaigns[campaignId];
        require(msg.sender == c.creator, "CampaignManager: Not campaign creator");
        require(c.status == CampaignStatus.ACTIVE, "CampaignManager: Campaign not active");
        require(targetAmount > 0 && targetAmount <= c.goalAmount, "CampaignManager: Invalid target");

        c.milestones.push(Milestone({
            title: title,
            description: description,
            targetAmount: targetAmount,
            isReached: false
        }));

        emit MilestoneAdded(campaignId, c.milestones.length - 1);
    }

    // ─────────────────────────────────────────────────────────────
    // State Updates (called by StartupFund only)
    // ─────────────────────────────────────────────────────────────

    /// @notice Update how much ETH has been raised for a campaign.
    ///         Called by StartupFund after each successful fundCampaign() call.
    /// @param campaignId        Target campaign
    /// @param amount            ETH amount added in this contribution (wei)
    /// @param isNewContributor  True if this contributor has never funded this campaign before
    function updateRaisedAmount(
        uint256 campaignId,
        uint256 amount,
        bool isNewContributor
    ) external override onlyAuthorized campaignExists(campaignId) {
        Campaign storage c = _campaigns[campaignId];
        c.raisedAmount += amount;
        if (isNewContributor) {
            c.backersCount++;
        }

        // Auto-check milestones
        for (uint256 i = 0; i < c.milestones.length; i++) {
            if (!c.milestones[i].isReached && c.raisedAmount >= c.milestones[i].targetAmount) {
                c.milestones[i].isReached = true;
                emit MilestoneReached(campaignId, i);
            }
        }
    }

    /// @notice Evaluate whether campaign status should change based on current time and raised amount.
    ///         Transitions ACTIVE → FUNDED or ACTIVE → CANCELLED.
    ///         Can be called by anyone (StartupFund calls it before withdraw/refund).
    function checkAndUpdateStatus(uint256 campaignId)
        external
        override
        campaignExists(campaignId)
    {
        Campaign storage c = _campaigns[campaignId];

        // Only ACTIVE campaigns can transition
        if (c.status != CampaignStatus.ACTIVE) return;

        if (c.raisedAmount >= c.goalAmount) {
            // Goal met (may still be before deadline — assignment allows early success)
            c.status = CampaignStatus.FUNDED;
            emit CampaignFunded(campaignId, c.raisedAmount);
        } else if (block.timestamp >= c.deadline) {
            // Deadline passed, goal not met
            c.status = CampaignStatus.CANCELLED;
            emit CampaignCancelled(campaignId);
        }
        // Otherwise: still ACTIVE, no change
    }

    // ─────────────────────────────────────────────────────────────
    // Read Functions
    // ─────────────────────────────────────────────────────────────

    /// @notice Get the core numeric/address fields of a campaign (used by StartupFund for validation).
    function getCampaignCore(uint256 campaignId)
        external
        view
        override
        campaignExists(campaignId)
        returns (
            address creator,
            uint256 goalAmount,
            uint256 raisedAmount,
            uint256 minContribution,
            uint256 deadline,
            uint8 status
        )
    {
        Campaign storage c = _campaigns[campaignId];
        return (
            c.creator,
            c.goalAmount,
            c.raisedAmount,
            c.minContribution,
            c.deadline,
            uint8(c.status)
        );
    }

    /// @notice Get campaign string metadata (identity/display fields).
    ///         Split from getCampaignStats to avoid EVM stack-too-deep (16-slot limit).
    ///         Frontend calls both and combines results.
    function getCampaignMeta(uint256 campaignId)
        external
        view
        campaignExists(campaignId)
        returns (
            uint256 id,
            address creator,
            string memory title,
            string memory slug,
            string memory shortDescription,
            string memory imageUrl,
            string memory category
        )
    {
        Campaign storage c = _campaigns[campaignId];
        return (
            c.id,
            c.creator,
            c.title,
            c.slug,
            c.shortDescription,
            c.imageUrl,
            c.category
        );
    }

    /// @notice Get campaign numeric/status fields (funding progress, deadline, etc.).
    ///         Call alongside getCampaignMeta to get the full picture.
    function getCampaignStats(uint256 campaignId)
        external
        view
        campaignExists(campaignId)
        returns (
            uint256 goalAmount,
            uint256 raisedAmount,
            uint256 minContribution,
            uint256 deadline,
            uint8 status,
            uint256 backersCount
        )
    {
        Campaign storage c = _campaigns[campaignId];
        return (
            c.goalAmount,
            c.raisedAmount,
            c.minContribution,
            c.deadline,
            uint8(c.status),
            c.backersCount
        );
    }

    /// @notice Get the full description of a campaign (separate call to avoid stack-too-deep).
    function getCampaignDescription(uint256 campaignId)
        external
        view
        campaignExists(campaignId)
        returns (string memory description)
    {
        return _campaigns[campaignId].description;
    }

    /// @notice Get milestones for a campaign.
    function getMilestones(uint256 campaignId)
        external
        view
        campaignExists(campaignId)
        returns (
            string[] memory titles,
            string[] memory descriptions,
            uint256[] memory targetAmounts,
            bool[] memory isReached
        )
    {
        Campaign storage c = _campaigns[campaignId];
        uint256 len = c.milestones.length;

        titles = new string[](len);
        descriptions = new string[](len);
        targetAmounts = new uint256[](len);
        isReached = new bool[](len);

        for (uint256 i = 0; i < len; i++) {
            titles[i] = c.milestones[i].title;
            descriptions[i] = c.milestones[i].description;
            targetAmounts[i] = c.milestones[i].targetAmount;
            isReached[i] = c.milestones[i].isReached;
        }
    }

    /// @notice Get the tags array for a campaign.
    ///         Split out to keep the other read functions below the stack-too-deep limit.
    function getCampaignTags(uint256 campaignId)
        external
        view
        campaignExists(campaignId)
        returns (string[] memory)
    {
        return _campaigns[campaignId].tags;
    }

    /// @notice Convenience: get status as a uint8 (0=PENDING, 1=ACTIVE, 2=FUNDED, 3=CANCELLED, 4=REJECTED).
    function getStatus(uint256 campaignId)
        external
        view
        campaignExists(campaignId)
        returns (uint8)
    {
        return uint8(_campaigns[campaignId].status);
    }

    /// @notice Edit a campaign's mutable text fields. Called by StartupFund
    ///         after creator + backers-count guards. Goal/deadline/min stay
    ///         locked once on chain. Tags get fully replaced.
    function editCampaign(
        uint256 campaignId,
        string memory newTitle,
        string memory newSlug,
        string memory newDescription,
        string memory newShortDescription,
        string memory newImageUrl,
        string memory newCategory,
        string[] memory newTags
    ) external onlyAuthorized campaignExists(campaignId) {
        Campaign storage c = _campaigns[campaignId];
        require(c.backersCount == 0, "CampaignManager: Already has backers");
        require(bytes(newTitle).length > 0, "CampaignManager: Title required");
        c.title            = newTitle;
        c.slug             = newSlug;
        c.description      = newDescription;
        c.shortDescription = newShortDescription;
        c.imageUrl         = newImageUrl;
        c.category         = newCategory;
        delete c.tags;
        for (uint256 i = 0; i < newTags.length; i++) {
            c.tags.push(newTags[i]);
        }
    }

    /// @notice Set profit-return terms for a campaign. Called by StartupFund
    ///         immediately after createCampaign() if the creator opted in.
    ///         Both fields are optional; passing both as 0 is a no-op.
    function setProfitTerms(uint256 campaignId, uint256 rate, uint256 returnDeadline)
        external
        onlyAuthorized
        campaignExists(campaignId)
    {
        if (rate == 0 && returnDeadline == 0) return;
        Campaign storage c = _campaigns[campaignId];
        require(c.profitReturnRate == 0 && c.profitReturnDeadline == 0,
            "CampaignManager: Profit terms already set");
        require(rate > 0 && rate <= 100,
            "CampaignManager: Profit return rate must be 1-100");
        require(returnDeadline > c.deadline,
            "CampaignManager: Return deadline must be after campaign deadline");
        c.profitReturnRate     = rate;
        c.profitReturnDeadline = returnDeadline;
    }

    /// @notice Get profit-return terms set at create time. Both 0 = no profit promised.
    function getProfitTerms(uint256 campaignId)
        external
        view
        campaignExists(campaignId)
        returns (uint256 rate, uint256 returnDeadline)
    {
        Campaign storage c = _campaigns[campaignId];
        return (c.profitReturnRate, c.profitReturnDeadline);
    }
}
