// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title MNE Ecosystem Treasury
/// @notice Holds the 53% Ecosystem Development allocation.
///         Owner (deployer initially, later DAO timelock) can release tokens.
contract MNEEcosystemTreasury is Ownable2Step {
    using SafeERC20 for IERC20;

    IERC20 public immutable TOKEN;

    event TokensReleased(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 requested, uint256 available);

    constructor(address _token, address _owner) Ownable(_owner) {
        if (_token == address(0)) revert ZeroAddress();
        TOKEN = IERC20(_token);
    }

    /// @notice Release tokens from the treasury
    /// @param to Recipient address
    /// @param amount Amount of tokens to release
    function release(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 bal = TOKEN.balanceOf(address(this));
        if (amount > bal) revert InsufficientBalance(amount, bal);

        TOKEN.safeTransfer(to, amount);
        emit TokensReleased(to, amount);
    }

    /// @notice View current token balance held by treasury
    function balance() external view returns (uint256) {
        return TOKEN.balanceOf(address(this));
    }
}
