// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

/// @title Voting Escrow (veMNE) — Lock MNE for Governance Voting Power
/// @notice Users lock MNE tokens for a fixed duration to receive multiplied voting power.
///         Positions are non-transferable. Delegation is supported via OZ Votes.
///         Implements IVotes (EIP-5805) for integration with OZ Governor.
contract VotingEscrow is Votes, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Lock {
        uint128 amount; // Raw MNE tokens locked
        uint64 unlockTime; // Timestamp when lock expires
        uint8 tier; // Lock tier index (0-3)
    }

    // --- Constants ---
    uint256 public constant NUM_TIERS = 4;
    uint256 public constant MULTIPLIER_BASE = 10000; // basis points denominator

    // Multipliers in basis points: 1.5x, 2x, 3x, 4x
    uint256[4] public MULTIPLIERS = [uint256(15000), 20000, 30000, 40000];

    // Lock durations: 6mo, 12mo, 24mo, 48mo
    uint64[4] public LOCK_DURATIONS = [uint64(180 days), 365 days, 730 days, 1461 days];

    // --- Immutables ---
    IERC20 public immutable TOKEN;

    // --- State ---
    mapping(address => Lock) public locks;
    uint256 public totalLocked; // Total raw MNE locked (for EVS calculation)

    // Track multiplied voting units per user (needed for _getVotingUnits)
    mapping(address => uint256) private _votingUnits;

    // --- Events ---
    event Locked(address indexed account, uint256 amount, uint8 tier, uint64 unlockTime);
    event LockExtended(address indexed account, uint8 oldTier, uint8 newTier, uint64 newUnlockTime);
    event Withdrawn(address indexed account, uint256 amount);

    // --- Errors ---
    error InvalidTier(uint8 tier);
    error ZeroAmount();
    error AlreadyLocked();
    error NotLocked();
    error LockNotExpired(uint64 unlockTime);
    error CannotReduceTier(uint8 currentTier, uint8 newTier);

    constructor(address _token) EIP712("Monee Voting Escrow", "1") {
        TOKEN = IERC20(_token);
    }

    // --- Clock: use timestamps for governance ---

    function clock() public view override returns (uint48) {
        return Time.timestamp();
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // --- Core Functions ---

    /// @notice Lock MNE tokens to receive voting power
    /// @param amount Raw MNE tokens to lock
    /// @param tier Lock tier (0=6mo/1.5x, 1=12mo/2x, 2=24mo/3x, 3=48mo/4x)
    function lock(uint256 amount, uint8 tier) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (tier >= NUM_TIERS) revert InvalidTier(tier);
        if (locks[msg.sender].amount != 0) revert AlreadyLocked();

        uint64 unlockTime = uint64(block.timestamp) + LOCK_DURATIONS[tier];
        uint256 votingPower = (amount * MULTIPLIERS[tier]) / MULTIPLIER_BASE;

        locks[msg.sender] = Lock({amount: uint128(amount), unlockTime: unlockTime, tier: tier});

        totalLocked += amount;
        _votingUnits[msg.sender] = votingPower;

        TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        _transferVotingUnits(address(0), msg.sender, votingPower);

        emit Locked(msg.sender, amount, tier, unlockTime);
    }

    /// @notice Extend lock to a higher tier (longer duration, higher multiplier)
    /// @param newTier New lock tier (must be higher than current)
    function extendLock(uint8 newTier) external nonReentrant {
        Lock storage userLock = locks[msg.sender];
        if (userLock.amount == 0) revert NotLocked();
        if (newTier >= NUM_TIERS) revert InvalidTier(newTier);
        if (newTier <= userLock.tier) revert CannotReduceTier(userLock.tier, newTier);

        uint8 oldTier = userLock.tier;
        uint256 amount = userLock.amount;

        uint256 oldVotingPower = (amount * MULTIPLIERS[oldTier]) / MULTIPLIER_BASE;
        uint256 newVotingPower = (amount * MULTIPLIERS[newTier]) / MULTIPLIER_BASE;
        uint256 diff = newVotingPower - oldVotingPower;

        uint64 newUnlockTime = uint64(block.timestamp) + LOCK_DURATIONS[newTier];

        userLock.tier = newTier;
        userLock.unlockTime = newUnlockTime;

        _votingUnits[msg.sender] = newVotingPower;
        _transferVotingUnits(address(0), msg.sender, diff);

        emit LockExtended(msg.sender, oldTier, newTier, newUnlockTime);
    }

    /// @notice Withdraw MNE tokens after lock expires
    function withdraw() external nonReentrant {
        Lock storage userLock = locks[msg.sender];
        if (userLock.amount == 0) revert NotLocked();
        if (block.timestamp < userLock.unlockTime) revert LockNotExpired(userLock.unlockTime);

        uint256 amount = userLock.amount;
        uint256 votingPower = _votingUnits[msg.sender];

        delete locks[msg.sender];
        totalLocked -= amount;
        _votingUnits[msg.sender] = 0;

        _transferVotingUnits(msg.sender, address(0), votingPower);
        TOKEN.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    // --- Votes Override ---

    /// @dev Returns the multiplied voting power for an account
    function _getVotingUnits(address account) internal view override returns (uint256) {
        return _votingUnits[account];
    }

    // --- View Helpers ---

    /// @notice Get the voting power for a given amount and tier (preview)
    function previewVotingPower(uint256 amount, uint8 tier) external view returns (uint256) {
        if (tier >= NUM_TIERS) revert InvalidTier(tier);
        return (amount * MULTIPLIERS[tier]) / MULTIPLIER_BASE;
    }

    /// @notice Get current voting units for an account
    function votingUnitsOf(address account) external view returns (uint256) {
        return _votingUnits[account];
    }
}
