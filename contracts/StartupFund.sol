// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./CampaignManager.sol";
import "./FundingVault.sol";
import "./RewardToken.sol";
import "./AccessControl.sol";
import "./CampaignVoting.sol";

/// @title StartupFund - Main orchestrator for the decentralised crowdfunding platform
/// @notice THIS is the only contract the frontend needs to talk to.
///         It wires together CampaignManager, FundingVault, RewardToken,
///         AccessControl, and CampaignVoting.
///
/// User flows:
///   1. Register:        accessControl.register()           (call AccessControl directly)
///   2. Create campaign: startupFund.createCampaign(...)    → campaign enters PENDING
///   3. Vote on it:      startupFund.vote(id, approve)      (community, during window)
///   4. Settle vote:     startupFund.settleVoting(id)       (anyone, after window closes)
///                                                          → campaign becomes ACTIVE or REJECTED
///   5. Fund campaign:   startupFund.fundCampaign(id)       { value: ETH }
///   6. Withdraw:        startupFund.withdraw(id)           (creator, after goal met)
///   7. Claim refund:    startupFund.claimRefund(id)        (contributor, if campaign failed)
///   8. View campaigns:  campaignManager.getCampaignMeta(id) / getCampaignStats(id)
///   9. View balance:    rewardToken.balanceOf(address)
contract StartupFund {

    // ─────────────────────────────────────────────────────────────
    // Sub-contract references
    // ─────────────────────────────────────────────────────────────

    CampaignManager public campaignManager;
    FundingVault    public fundingVault;
    RewardToken     public rewardToken;
    AccessControl   public accessControl;
    CampaignVoting  public campaignVoting;

    // ─────────────────────────────────────────────────────────────
    // Flag (community moderation) state
    // ─────────────────────────────────────────────────────────────

    /// @notice Flags required to auto-cancel an ACTIVE campaign + refund all backers.
    uint256 public constant FLAG_THRESHOLD = 5;

    /// @notice Number of unique wallets that have flagged a campaign.
    mapping(uint256 => uint256) public flagCount;

    /// @notice campaignId → flagger → has-flagged?
    mapping(uint256 => mapping(address => bool)) public hasFlagged;

    // ─────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────

    event CampaignCreatedVia(
        uint256 indexed campaignId,
        address indexed creator
    );
    event FundingReceived(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    event TokensMinted(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 tokens
    );
    event FundsWithdrawn(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 amount
    );
    event RefundClaimed(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    event CampaignFlagged(
        uint256 indexed campaignId,
        address indexed flagger,
        uint256 totalFlags
    );
    event CampaignUnflagged(
        uint256 indexed campaignId,
        address indexed flagger,
        uint256 totalFlags
    );
    event CampaignAutoCancelled(
        uint256 indexed campaignId,
        uint256 finalFlags
    );

    // ─────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────

    /// @dev Applied to all state-changing actions. Checks: registered + not blocked + not paused.
    modifier onlyRegistered() {
        require(
            accessControl.isRegistered(msg.sender),
            "StartupFund: Wallet not registered. Call accessControl.register() first."
        );
        require(
            !accessControl.isBlocked(msg.sender),
            "StartupFund: Wallet is blocked"
        );
        require(
            !accessControl.paused(),
            "StartupFund: Platform is paused"
        );
        _;
    }

    // ─────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────

    /// @notice Deploy after all 5 sub-contracts are deployed.
    ///         Then call:
    ///           CampaignManager.setAuthorized(address(this))
    ///           FundingVault.setAuthorized(address(this))
    ///           RewardToken.setMinter(address(this))
    ///           CampaignManager.setVotingContract(address(campaignVoting))
    ///           CampaignVoting.setAuthorized(address(this))
    constructor(
        address _campaignManager,
        address _fundingVault,
        address _rewardToken,
        address _accessControl,
        address _campaignVoting
    ) {
        require(_campaignManager != address(0), "StartupFund: Zero address");
        require(_fundingVault    != address(0), "StartupFund: Zero address");
        require(_rewardToken     != address(0), "StartupFund: Zero address");
        require(_accessControl   != address(0), "StartupFund: Zero address");
        require(_campaignVoting  != address(0), "StartupFund: Zero address");

        campaignManager = CampaignManager(_campaignManager);
        fundingVault    = FundingVault(_fundingVault);
        rewardToken     = RewardToken(_rewardToken);
        accessControl   = AccessControl(_accessControl);
        campaignVoting  = CampaignVoting(_campaignVoting);
    }

    // ─────────────────────────────────────────────────────────────
    // 1. Create Campaign
    // ─────────────────────────────────────────────────────────────

    /// @notice Create a new crowdfunding campaign.
    ///         Caller must be registered via accessControl.register() first.
    ///
    /// @param title             Startup/project name (non-empty)
    /// @param slug              URL slug e.g. "ecoflow-smart-grid"
    /// @param description       Full business plan
    /// @param shortDescription  Elevator pitch (for campaign card)
    /// @param imageUrl          Cover image URL or IPFS hash
    /// @param category          "Tech" | "Fintech" | "Healthcare" | "Green Energy" | "AI" | "Web3"
    /// @param goalAmount        Funding target in wei (e.g. 1 ETH = 1000000000000000000)
    /// @param minContribution   Minimum contribution in wei (min: 1000000000000000 = 0.001 ETH)
    /// @param deadline          Unix timestamp for campaign end (any future time, max 60 days from now)
    /// @param tags              Searchable labels, lowercased by convention (e.g. ["ai","climate"])
    /// @return campaignId       The ID of the newly created campaign
    /// @dev Campaign enters PENDING status. Community voting opens immediately.
    ///      Call settleVoting(id) after the window closes to transition it
    ///      to ACTIVE (fundable) or REJECTED.
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
    ) external onlyRegistered returns (uint256 campaignId) {
        campaignId = campaignManager.createCampaign(
            title, slug, description, shortDescription, imageUrl,
            category, goalAmount, minContribution, deadline, tags
        );

        // Open the community voting window immediately
        campaignVoting.openVoting(campaignId);

        emit CampaignCreatedVia(campaignId, msg.sender);
    }

    /// @notice Edit a campaign's text fields. Creator-only, before any backers.
    function editCampaign(
        uint256 campaignId,
        string memory newTitle,
        string memory newSlug,
        string memory newDescription,
        string memory newShortDescription,
        string memory newImageUrl,
        string memory newCategory,
        string[] memory newTags
    ) external onlyRegistered {
        (address creator, , , , , ) = campaignManager.getCampaignCore(campaignId);
        require(msg.sender == creator, "StartupFund: Only creator can edit");
        campaignManager.editCampaign(
            campaignId, newTitle, newSlug, newDescription,
            newShortDescription, newImageUrl, newCategory, newTags
        );
    }

    /// @notice Attach profit-return terms to a freshly-created campaign.
    ///         Must be called by the campaign creator. Settings are immutable
    ///         once set (one-shot). Skip this call if no profit return offered.
    /// @param campaignId    The campaign just returned by createCampaign()
    /// @param rate          Profit % (1-100). e.g. 50 = creator promises 1.5x payout.
    /// @param returnDeadline Unix timestamp; must be > campaign deadline.
    function setProfitTerms(uint256 campaignId, uint256 rate, uint256 returnDeadline)
        external
        onlyRegistered
    {
        (address creator, , , , , ) = campaignManager.getCampaignCore(campaignId);
        require(msg.sender == creator, "StartupFund: Only creator can set profit terms");
        campaignManager.setProfitTerms(campaignId, rate, returnDeadline);
    }

    // ─────────────────────────────────────────────────────────────
    // 2. Fund Campaign
    // ─────────────────────────────────────────────────────────────

    /// @notice Contribute ETH to an active campaign. Send ETH as msg.value.
    ///         Funds are locked in FundingVault until campaign settles.
    ///
    /// @param campaignId  Which campaign to fund
    ///
    /// Example (ethers.js):
    ///   await startupFund.fundCampaign(0, { value: ethers.parseEther("0.5") })
    function fundCampaign(uint256 campaignId) external payable onlyRegistered {
        // ── Read campaign state ──
        (
            address creator,
            uint256 goalAmount,
            uint256 raisedAmount,
            uint256 minContribution,
            uint256 deadline,
            uint8 status
        ) = campaignManager.getCampaignCore(campaignId);

        // status 1 = ACTIVE (0 = PENDING, 2 = FUNDED, 3 = CANCELLED, 4 = REJECTED)
        require(status == 1, "StartupFund: Campaign is not active");
        require(block.timestamp < deadline, "StartupFund: Campaign deadline has passed");
        require(msg.value >= minContribution, "StartupFund: Contribution below minimum");
        require(msg.sender != creator, "StartupFund: Creator cannot fund own campaign");

        // ── Deposit ETH; vault returns whether this is a first-time contributor ──
        bool isNewContributor = fundingVault.deposit{value: msg.value}(campaignId, msg.sender);

        // ── Update campaign raised amount ──
        campaignManager.updateRaisedAmount(campaignId, msg.value, isNewContributor);

        // ── Check if goal is now met → transition to FUNDED ──
        if (raisedAmount + msg.value >= goalAmount) {
            campaignManager.checkAndUpdateStatus(campaignId);
        }

        emit FundingReceived(campaignId, msg.sender, msg.value);
    }

    // ─────────────────────────────────────────────────────────────
    // 3. Withdraw (creator, after campaign succeeds)
    // ─────────────────────────────────────────────────────────────

    /// @notice Withdraw all raised ETH to the campaign creator's wallet.
    ///         Automatically mints SFT reward tokens to all contributors first.
    ///         Can only be called once per campaign.
    ///
    /// Requirements:
    ///   - Caller must be campaign creator
    ///   - Campaign status must be FUNDED (goal met)
    ///   - Funds must not have been released already
    ///
    /// @param campaignId  Which campaign to withdraw from
    function withdraw(uint256 campaignId) external onlyRegistered {
        // ── Get creator only (other fields read after status update below) ──
        (address creator, , , , , ) = campaignManager.getCampaignCore(campaignId);
        require(msg.sender == creator, "StartupFund: Only campaign creator can withdraw");

        // ── Ensure status is up-to-date ──
        // Deadline may have passed since last interaction; check will transition if needed.
        campaignManager.checkAndUpdateStatus(campaignId);

        // Re-read status after potential update
        (, , , , , uint8 currentStatus) = campaignManager.getCampaignCore(campaignId);
        require(currentStatus == 2, "StartupFund: Campaign not funded yet"); // 2 = FUNDED

        require(!fundingVault.fundsReleased(campaignId), "StartupFund: Already withdrawn");

        uint256 totalRaised = fundingVault.vaultBalance(campaignId);
        require(totalRaised > 0, "StartupFund: No funds to withdraw");

        // Release ETH from vault to creator. SFT minting removed — value to
        // backers comes via profit-return disbursement instead.
        fundingVault.releaseFunds(campaignId, msg.sender);

        emit FundsWithdrawn(campaignId, msg.sender, totalRaised);
    }

    // ─────────────────────────────────────────────────────────────
    // 4. Claim Refund (contributor, if campaign fails)
    // ─────────────────────────────────────────────────────────────

    /// @notice Claim a full refund if the campaign deadline passed without meeting its goal.
    ///         Each contributor can only claim once. Refunded contributors cannot receive tokens.
    ///
    /// Requirements:
    ///   - Campaign must be CANCELLED (deadline passed, goal not met)
    ///   - Caller must have contributed to this campaign
    ///   - Caller must not have already claimed a refund
    ///
    /// @param campaignId  Which campaign to claim a refund from
    function claimRefund(uint256 campaignId) external onlyRegistered {
        // ── Ensure status is up-to-date (auto-cancel if deadline passed) ──
        campaignManager.checkAndUpdateStatus(campaignId);

        (, , , , , uint8 currentStatus) = campaignManager.getCampaignCore(campaignId);
        require(currentStatus == 3, "StartupFund: Campaign not cancelled"); // 3 = CANCELLED

        uint256 contribution = fundingVault.getContribution(campaignId, msg.sender);
        require(contribution > 0, "StartupFund: No contribution found for this wallet");
        require(
            !fundingVault.refundClaimed(campaignId, msg.sender),
            "StartupFund: Refund already claimed"
        );

        // FundingVault handles the CEI pattern internally
        fundingVault.issueRefund(campaignId, msg.sender);

        emit RefundClaimed(campaignId, msg.sender, contribution);
    }

    // ─────────────────────────────────────────────────────────────
    // Flag (community moderation)
    // ─────────────────────────────────────────────────────────────

    /// @notice Flag an ACTIVE campaign. Once FLAG_THRESHOLD unique wallets have
    ///         flagged, the campaign is force-cancelled and ALL contributors are
    ///         refunded automatically in this same tx.
    /// @dev Caller must be registered, not the creator, and not have flagged
    ///      this campaign already. Self-flag is blocked.
    function flagCampaign(uint256 campaignId) external onlyRegistered {
        (address creator, , , , , uint8 status) = campaignManager.getCampaignCore(campaignId);
        require(status == 1, "StartupFund: Campaign not active"); // 1 = ACTIVE
        require(msg.sender != creator, "StartupFund: Creator cannot flag own campaign");
        require(!hasFlagged[campaignId][msg.sender], "StartupFund: Already flagged");

        hasFlagged[campaignId][msg.sender] = true;
        flagCount[campaignId]++;
        emit CampaignFlagged(campaignId, msg.sender, flagCount[campaignId]);

        if (flagCount[campaignId] >= FLAG_THRESHOLD) {
            // Force-cancel and refund every contributor in one shot.
            campaignManager.forceCancelCampaign(campaignId);
            emit CampaignAutoCancelled(campaignId, flagCount[campaignId]);

            address[] memory contribs = fundingVault.getContributors(campaignId);
            for (uint256 i = 0; i < contribs.length; i++) {
                address c = contribs[i];
                if (fundingVault.refundClaimed(campaignId, c)) continue;
                uint256 amount = fundingVault.getContribution(campaignId, c);
                if (amount == 0) continue;
                fundingVault.issueRefund(campaignId, c);
                emit RefundClaimed(campaignId, c, amount);
            }
        }
    }

    // ─────────────────────────────────────────────────────────────
    // Profit Disbursement (creator funnels back, backers paid out)
    // ─────────────────────────────────────────────────────────────

    event PayoutPotFunded(uint256 indexed campaignId, uint256 amount);
    event ProfitsDisbursed(uint256 indexed campaignId, uint256 totalPaid);

    /// @notice Compute exact wei the creator must deposit for the payout pot.
    ///         payoutRequired = raised * (100 + profitReturnRate) / 100
    function payoutRequired(uint256 campaignId) public view returns (uint256) {
        (, , uint256 raised, , , ) = campaignManager.getCampaignCore(campaignId);
        (uint256 rate, ) = campaignManager.getProfitTerms(campaignId);
        return raised + (raised * rate) / 100;
    }

    /// @notice Creator deposits the exact payout pot for a FUNDED campaign.
    ///         msg.value must equal payoutRequired(id) — overpay/underpay reverts.
    function fundPayoutPot(uint256 campaignId) external payable onlyRegistered {
        (address creator, , , , , uint8 status) = campaignManager.getCampaignCore(campaignId);
        require(status == 2, "StartupFund: Campaign not funded"); // 2 = FUNDED
        require(msg.sender == creator, "StartupFund: Only creator can fund payout");
        (uint256 rate, uint256 returnDeadline) = campaignManager.getProfitTerms(campaignId);
        require(returnDeadline > 0 && rate > 0, "StartupFund: No profit return promised");
        require(block.timestamp < returnDeadline, "StartupFund: Return deadline already passed");
        require(fundingVault.payoutPot(campaignId) == 0, "StartupFund: Payout already deposited");

        uint256 required = payoutRequired(campaignId);
        require(msg.value == required, "StartupFund: Must deposit exact payout amount");

        fundingVault.depositPayout{value: msg.value}(campaignId, msg.sender);
        emit PayoutPotFunded(campaignId, msg.value);
    }

    /// @notice Disburse the payout pot to all backers proportional to their
    ///         contribution. Permissionless trigger; one-shot. Lazy-fire from UI.
    function disburseProfits(uint256 campaignId) external onlyRegistered {
        (, , uint256 raised, , , uint8 status) = campaignManager.getCampaignCore(campaignId);
        require(status == 2, "StartupFund: Campaign not funded");
        (, uint256 returnDeadline) = campaignManager.getProfitTerms(campaignId);
        require(returnDeadline > 0, "StartupFund: No profit return promised");
        require(block.timestamp >= returnDeadline, "StartupFund: Return deadline not reached");
        require(!fundingVault.payoutDisbursed(campaignId), "StartupFund: Already disbursed");

        uint256 pot = fundingVault.payoutPot(campaignId);
        require(pot > 0, "StartupFund: Payout pot empty");
        require(raised > 0, "StartupFund: Nothing was raised");

        // Snapshot contribution per backer at withdraw was preserved on chain
        // via FundingReceived events. The vault's `contributions` mapping was
        // NOT zeroed during withdraw (only during refund), so it still holds
        // each backer's principal — we use that as the share weight.
        address[] memory contribs = fundingVault.getContributors(campaignId);
        uint256 totalPaid = 0;

        for (uint256 i = 0; i < contribs.length; i++) {
            address backer = contribs[i];
            // Refunded backers don't get profit — their contribution was already returned
            if (fundingVault.refundClaimed(campaignId, backer)) continue;
            uint256 share = fundingVault.getContribution(campaignId, backer);
            if (share == 0) continue;
            uint256 owe = (pot * share) / raised;
            if (owe == 0) continue;
            fundingVault.sendPayout(campaignId, backer, owe);
            totalPaid += owe;
        }

        fundingVault.markPayoutDisbursed(campaignId);
        emit ProfitsDisbursed(campaignId, totalPaid);
    }

    /// @notice Withdraw a previously cast flag. Only allowed while still ACTIVE.
    function unflagCampaign(uint256 campaignId) external onlyRegistered {
        require(hasFlagged[campaignId][msg.sender], "StartupFund: Not flagged");
        (, , , , , uint8 status) = campaignManager.getCampaignCore(campaignId);
        require(status == 1, "StartupFund: Campaign no longer active");
        hasFlagged[campaignId][msg.sender] = false;
        flagCount[campaignId]--;
        emit CampaignUnflagged(campaignId, msg.sender, flagCount[campaignId]);
    }

    /// @notice Refund every unclaimed contributor on a CANCELLED campaign in one tx.
    ///         Permissionless trigger (must be registered). Idempotent — skips
    ///         contributors who've already claimed. Used for lazy auto-fire when
    ///         the first visitor lands on a CANCELLED campaign.
    /// @dev Gas scales linearly with contributor count. For the demo's small
    ///      contributor pools (<20) this is fine. Per-contributor claimRefund
    ///      remains as a fallback for large campaigns.
    function refundAll(uint256 campaignId) external onlyRegistered {
        // Ensure status reflects current time (auto-cancel if deadline passed)
        campaignManager.checkAndUpdateStatus(campaignId);
        (, , , , , uint8 currentStatus) = campaignManager.getCampaignCore(campaignId);
        require(currentStatus == 3, "StartupFund: Campaign not cancelled"); // 3 = CANCELLED

        address[] memory contributors = fundingVault.getContributors(campaignId);
        uint256 refundedCount = 0;

        for (uint256 i = 0; i < contributors.length; i++) {
            address c = contributors[i];
            if (fundingVault.refundClaimed(campaignId, c)) continue;
            uint256 amount = fundingVault.getContribution(campaignId, c);
            if (amount == 0) continue;

            fundingVault.issueRefund(campaignId, c);
            emit RefundClaimed(campaignId, c, amount);
            refundedCount++;
        }

        require(refundedCount > 0, "StartupFund: Nothing to refund");
    }

    // ─────────────────────────────────────────────────────────────
    // 5. Convenience read (so frontend can call one contract)
    // ─────────────────────────────────────────────────────────────

    /// @notice Get current SFT token balance of an address.
    function tokenBalanceOf(address wallet) external view returns (uint256) {
        return rewardToken.balanceOf(wallet);
    }

    /// @notice Get total number of campaigns created.
    function totalCampaigns() external view returns (uint256) {
        return campaignManager.campaignCount();
    }

    /// @notice Check if an address is registered.
    function isRegistered(address wallet) external view returns (bool) {
        return accessControl.isRegistered(wallet);
    }

    // ─────────────────────────────────────────────────────────────
    // 6. Community Voting passthroughs
    // ─────────────────────────────────────────────────────────────

    /// @notice Vote to approve (true) or disapprove (false) a PENDING campaign.
    ///         Caller must be registered. One vote per wallet per campaign.
    function vote(uint256 campaignId, bool approve) external onlyRegistered {
        campaignVoting.vote(campaignId, approve);
    }

    /// @notice Settle voting once the window has closed. Anyone can call.
    ///         Transitions the campaign from PENDING → ACTIVE or PENDING → REJECTED.
    function settleVoting(uint256 campaignId) external {
        campaignVoting.settleVoting(campaignId);
    }

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
        return campaignVoting.getVoteStatus(campaignId);
    }

    /// @notice Whether a given wallet has already voted on a campaign.
    function hasVoted(uint256 campaignId, address voter) external view returns (bool) {
        return campaignVoting.hasVoted(campaignId, voter);
    }

    /// @notice Seconds left in the voting window. 0 if closed or not opened.
    function votingTimeRemaining(uint256 campaignId) external view returns (uint256) {
        return campaignVoting.timeRemaining(campaignId);
    }
}
