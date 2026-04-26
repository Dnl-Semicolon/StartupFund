// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title IVerification - Interface for wallet verification and access control
/// @notice Implemented by AccessControl.sol
interface IVerification {
    function isRegistered(address wallet) external view returns (bool);
    function isBlocked(address wallet) external view returns (bool);
    function paused() external view returns (bool);
    /// @notice Register the calling wallet. Automatically grants entrepreneur role.
    function register() external;
    function isEntrepreneur(address wallet) external view returns (bool);
}
