// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title FundingVault - ETH escrow for all campaign contributions
/// @notice Holds ETH on behalf of campaigns. Only the StartupFund orchestrator
///         can move funds — contributors cannot withdraw directly.
///         Separating fund storage from campaign logic is a key security pattern:
///         if StartupFund is ever upgraded, the vault stays intact.
/// @dev Uses CEI (Checks-Effects-Interactions) pattern for all ETH transfers.
///      Uses .call{value}("") instead of .transfer() — matches sample contract style.
contract FundingVault {

    // ─────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────

    /// @notice Total ETH currently held in the vault per campaign
    mapping(uint256 => uint256) public vaultBalance;

    /// @notice How much ETH each contributor deposited into each campaign
    /// campaignId → contributor address → total wei deposited
    mapping(uint256 => mapping(address => uint256)) public contributions;

    /// @notice Ordered list of contributor addresses per campaign.
    ///         Required for the token minting loop in withdraw().
    mapping(uint256 => address[]) private _contributorList;

    /// @notice Whether a contributor has already claimed their refund for a campaign
    mapping(uint256 => mapping(address => bool)) public refundClaimed;

    /// @notice Whether the creator has already withdrawn funds for a campaign (once only)
    mapping(uint256 => bool) public fundsReleased;

    /// @notice Creator-deposited payout pot (raised + profit). One-shot exact deposit.
    mapping(uint256 => uint256) public payoutPot;

    /// @notice Whether the payout has already been disbursed to backers (once only)
    mapping(uint256 => bool) public payoutDisbursed;

    address public owner;
    address public authorized; // = StartupFund contract

    // ─────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────

    event Deposited(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    event FundsReleased(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 amount
    );
    event RefundIssued(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );
    event PayoutDeposited(
        uint256 indexed campaignId,
        address indexed creator,
        uint256 amount
    );
    event PayoutSent(
        uint256 indexed campaignId,
        address indexed contributor,
        uint256 amount
    );

    // ─────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        require(msg.sender == owner, "FundingVault: Not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == authorized, "FundingVault: Not authorized");
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
        require(_authorized != address(0), "FundingVault: Zero address");
        authorized = _authorized;
    }

    // ─────────────────────────────────────────────────────────────
    // Deposit
    // ─────────────────────────────────────────────────────────────

    /// @notice Accept ETH contribution for a campaign. Called by StartupFund.fundCampaign().
    /// @param campaignId   Which campaign receives the funds
    /// @param contributor  The contributor's wallet address (msg.sender in StartupFund)
    /// @return isNewContributor  True if this is the contributor's first deposit to this campaign
    function deposit(uint256 campaignId, address contributor)
        external
        payable
        onlyAuthorized
        returns (bool isNewContributor)
    {
        require(msg.value > 0, "FundingVault: No ETH sent");

        // Detect first-time contributor (before adding to balance)
        isNewContributor = (contributions[campaignId][contributor] == 0);
        if (isNewContributor) {
            _contributorList[campaignId].push(contributor);
        }

        contributions[campaignId][contributor] += msg.value;
        vaultBalance[campaignId] += msg.value;

        emit Deposited(campaignId, contributor, msg.value);
    }

    // ─────────────────────────────────────────────────────────────
    // Release Funds (successful campaign)
    // ─────────────────────────────────────────────────────────────

    /// @notice Release all campaign ETH to the campaign creator. Called by StartupFund.withdraw().
    ///         Can only happen once per campaign. Tokens must be minted before this is called.
    /// @param campaignId     Which campaign to release
    /// @param creatorAddress The creator's wallet to receive the ETH
    function releaseFunds(uint256 campaignId, address creatorAddress)
        external
        onlyAuthorized
    {
        require(!fundsReleased[campaignId], "FundingVault: Already released");
        require(creatorAddress != address(0), "FundingVault: Zero address");

        uint256 amount = vaultBalance[campaignId];
        require(amount > 0, "FundingVault: No funds to release");

        // ── CEI: Update state BEFORE transferring ETH ──
        fundsReleased[campaignId] = true;
        vaultBalance[campaignId] = 0;

        // Transfer ETH using .call (safer than .transfer — no gas limit)
        (bool success, ) = payable(creatorAddress).call{value: amount}("");
        require(success, "FundingVault: ETH transfer failed");

        emit FundsReleased(campaignId, creatorAddress, amount);
    }

    // ─────────────────────────────────────────────────────────────
    // Refund (failed campaign)
    // ─────────────────────────────────────────────────────────────

    /// @notice Refund a contributor's ETH. Called by StartupFund.claimRefund().
    ///         Each contributor can only claim once per campaign.
    /// @param campaignId   Which campaign to refund from
    /// @param contributor  The contributor requesting the refund
    function issueRefund(uint256 campaignId, address contributor)
        external
        onlyAuthorized
    {
        require(
            !refundClaimed[campaignId][contributor],
            "FundingVault: Refund already claimed"
        );

        uint256 amount = contributions[campaignId][contributor];
        require(amount > 0, "FundingVault: Nothing to refund");

        // ── CEI: Update state BEFORE transferring ETH ──
        refundClaimed[campaignId][contributor] = true;
        contributions[campaignId][contributor] = 0;
        vaultBalance[campaignId] -= amount;

        // Transfer ETH back to contributor
        (bool success, ) = payable(contributor).call{value: amount}("");
        require(success, "FundingVault: ETH refund failed");

        emit RefundIssued(campaignId, contributor, amount);
    }

    // ─────────────────────────────────────────────────────────────
    // Read Functions
    // ─────────────────────────────────────────────────────────────

    /// @notice Get all contributor addresses for a campaign.
    ///         Used by StartupFund.withdraw() to loop and mint tokens to each.
    function getContributors(uint256 campaignId)
        external
        view
        returns (address[] memory)
    {
        return _contributorList[campaignId];
    }

    /// @notice Get how much a specific contributor deposited into a campaign.
    ///         Used by StartupFund.withdraw() to calculate token mint amount.
    function getContribution(uint256 campaignId, address contributor)
        external
        view
        returns (uint256)
    {
        return contributions[campaignId][contributor];
    }

    /// @notice Get total number of unique contributors to a campaign.
    function getContributorCount(uint256 campaignId)
        external
        view
        returns (uint256)
    {
        return _contributorList[campaignId].length;
    }

    // ─────────────────────────────────────────────────────────────
    // Payout Pot (creator-funded post-campaign profit return)
    // ─────────────────────────────────────────────────────────────

    /// @notice Stash the creator-deposited payout (principal + profit) for later disbursement.
    function depositPayout(uint256 campaignId, address creator)
        external
        payable
        onlyAuthorized
    {
        require(!payoutDisbursed[campaignId], "FundingVault: Payout already disbursed");
        require(payoutPot[campaignId] == 0,    "FundingVault: Payout already deposited");
        require(msg.value > 0,                 "FundingVault: No ETH sent");
        payoutPot[campaignId] = msg.value;
        emit PayoutDeposited(campaignId, creator, msg.value);
    }

    /// @notice Send `amount` from the payout pot to `recipient`. Caller must
    ///         track per-recipient amounts (StartupFund.disburseProfits does).
    function sendPayout(uint256 campaignId, address recipient, uint256 amount)
        external
        onlyAuthorized
    {
        require(!payoutDisbursed[campaignId], "FundingVault: Payout already disbursed");
        require(amount > 0,                   "FundingVault: Zero amount");
        require(amount <= payoutPot[campaignId], "FundingVault: Amount exceeds pot");

        payoutPot[campaignId] -= amount;
        (bool ok, ) = payable(recipient).call{value: amount}("");
        require(ok, "FundingVault: Payout transfer failed");
        emit PayoutSent(campaignId, recipient, amount);
    }

    /// @notice Mark the payout as fully disbursed. Called by StartupFund after the loop.
    function markPayoutDisbursed(uint256 campaignId) external onlyAuthorized {
        require(!payoutDisbursed[campaignId], "FundingVault: Already disbursed");
        payoutDisbursed[campaignId] = true;
    }
}
