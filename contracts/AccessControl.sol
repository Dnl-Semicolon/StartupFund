// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./IVerification.sol";

/// @title AccessControl - Platform-wide user registration and access control
/// @notice register() assigns both Contributor and Entrepreneur roles in one tx.
///         No separate becomeEntrepreneur() step — wallet = identity.
contract AccessControl is IVerification {

    address public owner;
    bool public override paused;

    mapping(address => bool) public blockedWallets;
    mapping(address => bool) public registeredUsers;
    mapping(address => bool) private entrepreneurUsers;

    event Paused(address indexed admin);
    event Unpaused(address indexed admin);
    event WalletBlocked(address indexed wallet);
    event WalletUnblocked(address indexed wallet);
    event UserRegistered(address indexed wallet);

    modifier onlyOwner() {
        require(msg.sender == owner, "AccessControl: Not owner");
        _;
    }

    modifier notBlocked() {
        require(!blockedWallets[msg.sender], "AccessControl: Wallet blocked");
        _;
    }

    constructor() {
        owner = msg.sender;
        paused = false;
    }

    /// @notice Register the calling wallet. Grants both roles atomically. Call once per wallet.
    function register() external override notBlocked {
        require(!registeredUsers[msg.sender], "AccessControl: Already registered");
        registeredUsers[msg.sender] = true;
        entrepreneurUsers[msg.sender] = true;
        emit UserRegistered(msg.sender);
    }

    function isRegistered(address wallet) external view override returns (bool) {
        return registeredUsers[wallet];
    }

    function isBlocked(address wallet) external view override returns (bool) {
        return blockedWallets[wallet];
    }

    function isEntrepreneur(address wallet) external view override returns (bool) {
        return entrepreneurUsers[wallet];
    }

    function pause() external onlyOwner {
        require(!paused, "AccessControl: Already paused");
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        require(paused, "AccessControl: Not paused");
        paused = false;
        emit Unpaused(msg.sender);
    }

    function blockWallet(address wallet) external onlyOwner {
        require(wallet != owner, "AccessControl: Cannot block owner");
        blockedWallets[wallet] = true;
        emit WalletBlocked(wallet);
    }

    function unblockWallet(address wallet) external onlyOwner {
        blockedWallets[wallet] = false;
        emit WalletUnblocked(wallet);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "AccessControl: Zero address");
        owner = newOwner;
    }
}
