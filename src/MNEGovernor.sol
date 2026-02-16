// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VotingEscrow} from "./VotingEscrow.sol";

/// @title MNE Governor — Monee DAO Governance
/// @notice On-chain governance for the Monee ecosystem. Uses veMNE voting power
///         from VotingEscrow. Quorum is based on Effective Voting Supply (EVS).
///         Proposals are executed through a TimelockController with 48-hour delay.
contract MNEGovernor is Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes, GovernorTimelockControl {
    // --- Quorum State ---
    uint256 private _quorumNumerator; // percentage of EVS required (default: 12)
    uint256 private _foundationHeldTokens; // tokens held by foundation (excluded from EVS)

    IERC20 public immutable MNE_TOKEN;
    VotingEscrow public immutable VOTING_ESCROW;

    // --- Events ---
    event QuorumNumeratorUpdated(uint256 oldNumerator, uint256 newNumerator);
    event FoundationHeldTokensUpdated(uint256 oldAmount, uint256 newAmount);

    // --- Errors ---
    error QuorumNumeratorTooHigh(uint256 numerator);

    constructor(
        VotingEscrow votingEscrow_,
        TimelockController timelock_,
        IERC20 mneToken_
    )
        Governor("MNE Governor")
        GovernorSettings(
            1 days,       // votingDelay: 1 day
            3 days,       // votingPeriod: 3 days (72 hours)
            7_000_000e18  // proposalThreshold: 7M veMNE (0.1% of 7B supply)
        )
        GovernorVotes(IVotes(address(votingEscrow_)))
        GovernorTimelockControl(timelock_)
    {
        MNE_TOKEN = mneToken_;
        VOTING_ESCROW = votingEscrow_;
        _quorumNumerator = 12; // 12% of EVS
    }

    // --- Quorum (custom EVS-based) ---

    /// @notice Returns the quorum for a proposal based on Effective Voting Supply
    /// @dev EVS = totalSupply - lockedInEscrow - foundationHeld
    ///      Quorum = EVS * _quorumNumerator / 100
    ///      Note: timepoint parameter is accepted for interface compatibility but
    ///      EVS is calculated from current state (totalLocked is not checkpointed).
    function quorum(uint256 /* timepoint */ ) public view override returns (uint256) {
        uint256 totalMNE = MNE_TOKEN.totalSupply();
        uint256 locked = VOTING_ESCROW.totalLocked();
        uint256 foundation = _foundationHeldTokens;

        uint256 evs = totalMNE - locked - foundation;
        return (evs * _quorumNumerator) / 100;
    }

    /// @notice Current quorum numerator (percentage)
    function quorumNumerator() external view returns (uint256) {
        return _quorumNumerator;
    }

    /// @notice Current foundation-held token amount excluded from EVS
    function foundationHeldTokens() external view returns (uint256) {
        return _foundationHeldTokens;
    }

    /// @notice Update quorum percentage (only via governance)
    function setQuorumNumerator(uint256 newNumerator) external onlyGovernance {
        if (newNumerator > 100) revert QuorumNumeratorTooHigh(newNumerator);
        uint256 old = _quorumNumerator;
        _quorumNumerator = newNumerator;
        emit QuorumNumeratorUpdated(old, newNumerator);
    }

    /// @notice Update foundation-held tokens (only via governance)
    /// @dev As the Foundation releases tokens into circulation, this should decrease
    function setFoundationHeldTokens(uint256 newAmount) external onlyGovernance {
        uint256 old = _foundationHeldTokens;
        _foundationHeldTokens = newAmount;
        emit FoundationHeldTokensUpdated(old, newAmount);
    }

    // --- Required Overrides (diamond resolution) ---

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
