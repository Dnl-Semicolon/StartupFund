// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

/// @title RewardToken - Minimal token for StartupFund contributors
/// @notice No imports. No OpenZeppelin. Compiles instantly in Remix.
///         Has the 5 fields MetaMask needs to display it as a token:
///         name, symbol, decimals, balanceOf, Transfer event.
///         Only StartupFund contract can mint (set via setMinter after deploy).
contract RewardToken {

    string public name     = "StartupFund Token";
    string public symbol   = "SFT";
    uint8  public decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    address public minter;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event MinterChanged(address indexed oldMinter, address indexed newMinter);

    constructor() {
        minter = msg.sender;
    }

    /// @notice Hand minting rights to StartupFund. Call once after deploying StartupFund.
    function setMinter(address _minter) external {
        require(msg.sender == minter, "RewardToken: Not authorized");
        require(_minter != address(0), "RewardToken: Zero address");
        emit MinterChanged(minter, _minter);
        minter = _minter;
    }

    /// @notice Mint tokens to a contributor. Called by StartupFund during withdraw().
    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "RewardToken: Not authorized");
        require(to != address(0), "RewardToken: Zero address");
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount); // address(0) as sender = standard mint convention
    }
}
