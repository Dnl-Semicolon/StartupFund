// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title ICampaign - Interface for campaign management operations
/// @notice Implemented by CampaignManager.sol
interface ICampaign {
    /// @notice Create a new crowdfunding campaign
    /// @return campaignId The ID of the newly created campaign
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
        string memory tokenSymbol,
        string[] memory tags
    ) external returns (uint256 campaignId);

    function setProfitTerms(uint256 campaignId, uint256 rate, uint256 returnDeadline) external;

    /// @notice Get core campaign details
    function getCampaignCore(uint256 campaignId) external view returns (
        address creator,
        uint256 goalAmount,
        uint256 raisedAmount,
        uint256 minContribution,
        uint256 deadline,
        uint8 status
    );

    /// @notice Update raised amount and optionally backer count after a contribution
    function updateRaisedAmount(uint256 campaignId, uint256 amount, bool isNewContributor) external;

    /// @notice Check deadline and goal, update status to FUNDED or CANCELLED if needed
    function checkAndUpdateStatus(uint256 campaignId) external;

    /// @notice Activate a PENDING campaign. Called by CampaignVoting after approval.
    function activateCampaign(uint256 campaignId) external;

    /// @notice Reject a PENDING campaign. Called by CampaignVoting after disapproval.
    function rejectCampaign(uint256 campaignId) external;

    /// @notice Total number of campaigns created
    function campaignCount() external view returns (uint256);
}
