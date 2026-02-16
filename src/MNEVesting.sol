// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title MNE Vesting — Multi-Beneficiary Cliff + Linear Vesting
/// @notice Immutable vesting contract. Deploy one per allocation category.
///         Setup phase: owner adds beneficiaries. After finalize(), no changes possible.
contract MNEVesting is Ownable2Step {
    using SafeERC20 for IERC20;

    // --- Immutable parameters (set in constructor) ---
    IERC20 public immutable TOKEN;
    uint64 public immutable START;
    uint64 public immutable CLIFF_DURATION;
    uint64 public immutable VESTING_DURATION;

    // --- State ---
    bool public finalized;
    uint256 public totalAllocated;
    mapping(address => uint256) public allocations;
    mapping(address => uint256) public released;

    // --- Events ---
    event BeneficiaryAdded(address indexed beneficiary, uint256 amount);
    event TokensReleased(address indexed beneficiary, uint256 amount);
    event VestingFinalized(uint256 totalAllocated);

    // --- Errors ---
    error AlreadyFinalized();
    error NotFinalized();
    error ZeroAddress();
    error ZeroAmount();
    error BeneficiaryExists(address beneficiary);
    error ArrayLengthMismatch();
    error InsufficientBalance(uint256 required, uint256 available);
    error NothingToRelease();
    error NotBeneficiary();

    /// @param _token MNE token address
    /// @param _start TGE timestamp (vesting clock starts here)
    /// @param _cliffDuration Cliff period in seconds (no tokens releasable during cliff)
    /// @param _vestingDuration Linear vesting period in seconds (after cliff)
    constructor(
        address _token,
        uint64 _start,
        uint64 _cliffDuration,
        uint64 _vestingDuration,
        address _owner
    ) Ownable(_owner) {
        if (_token == address(0)) revert ZeroAddress();
        TOKEN = IERC20(_token);
        START = _start;
        CLIFF_DURATION = _cliffDuration;
        VESTING_DURATION = _vestingDuration;
    }

    // --- Setup Phase (pre-finalize only) ---

    /// @notice Add beneficiaries with their token allocations. Only callable before finalize().
    /// @param beneficiaries Array of beneficiary addresses
    /// @param amounts Array of token amounts (with decimals)
    function addBeneficiaries(address[] calldata beneficiaries, uint256[] calldata amounts) external onlyOwner {
        if (finalized) revert AlreadyFinalized();
        if (beneficiaries.length != amounts.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            if (beneficiaries[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();
            if (allocations[beneficiaries[i]] != 0) revert BeneficiaryExists(beneficiaries[i]);

            allocations[beneficiaries[i]] = amounts[i];
            totalAllocated += amounts[i];
            emit BeneficiaryAdded(beneficiaries[i], amounts[i]);
        }
    }

    /// @notice Permanently lock the contract. Verifies token balance covers all allocations.
    function finalize() external onlyOwner {
        if (finalized) revert AlreadyFinalized();

        uint256 bal = TOKEN.balanceOf(address(this));
        if (bal < totalAllocated) revert InsufficientBalance(totalAllocated, bal);

        finalized = true;
        emit VestingFinalized(totalAllocated);
    }

    // --- Vesting Phase (post-finalize) ---

    /// @notice Claim vested tokens. Caller must be a beneficiary.
    function release() external {
        if (!finalized) revert NotFinalized();
        if (allocations[msg.sender] == 0) revert NotBeneficiary();

        uint256 amount = releasable(msg.sender);
        if (amount == 0) revert NothingToRelease();

        released[msg.sender] += amount;
        TOKEN.safeTransfer(msg.sender, amount);
        emit TokensReleased(msg.sender, amount);
    }

    // --- View Functions ---

    /// @notice Amount of tokens currently claimable by a beneficiary
    function releasable(address beneficiary) public view returns (uint256) {
        return vestedAmount(beneficiary, uint64(block.timestamp)) - released[beneficiary];
    }

    /// @notice Total tokens vested for a beneficiary at a given timestamp
    function vestedAmount(address beneficiary, uint64 timestamp) public view returns (uint256) {
        uint256 allocation = allocations[beneficiary];
        if (allocation == 0) return 0;

        uint64 cliffEnd = START + CLIFF_DURATION;

        if (timestamp < cliffEnd) {
            return 0;
        }

        if (VESTING_DURATION == 0) {
            return allocation;
        }

        uint64 vestEnd = cliffEnd + VESTING_DURATION;

        if (timestamp >= vestEnd) {
            return allocation;
        }

        return (allocation * (timestamp - cliffEnd)) / VESTING_DURATION;
    }
}
