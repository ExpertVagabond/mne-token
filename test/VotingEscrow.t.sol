// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MNEToken} from "../src/MNEToken.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";

contract VotingEscrowTest is Test {
    MNEToken public token;
    VotingEscrow public escrow;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    uint256 public constant LOCK_AMOUNT = 1_000_000 * 10 ** 18;
    uint256 public constant MULTIPLIER_BASE = 10000;

    function setUp() public {
        token = new MNEToken();
        escrow = new VotingEscrow(address(token));

        // Fund alice and bob
        token.transfer(alice, 10_000_000 * 10 ** 18);
        token.transfer(bob, 10_000_000 * 10 ** 18);

        // Approve escrow
        vm.prank(alice);
        token.approve(address(escrow), type(uint256).max);
        vm.prank(bob);
        token.approve(address(escrow), type(uint256).max);
    }

    // ===== Lock Tests =====

    function test_Lock_Tier0() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        (uint128 amount, uint64 unlockTime, uint8 tier) = escrow.locks(alice);
        assertEq(amount, LOCK_AMOUNT);
        assertEq(tier, 0);
        assertEq(unlockTime, uint64(block.timestamp) + 180 days);

        // 1.5x multiplier = 15000 / 10000
        uint256 expectedPower = (LOCK_AMOUNT * 15000) / MULTIPLIER_BASE;
        assertEq(escrow.votingUnitsOf(alice), expectedPower);
    }

    function test_Lock_Tier1() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 1);

        (, , uint8 tier) = escrow.locks(alice);
        assertEq(tier, 1);

        uint256 expectedPower = (LOCK_AMOUNT * 20000) / MULTIPLIER_BASE;
        assertEq(escrow.votingUnitsOf(alice), expectedPower);
    }

    function test_Lock_Tier2() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 2);

        uint256 expectedPower = (LOCK_AMOUNT * 30000) / MULTIPLIER_BASE;
        assertEq(escrow.votingUnitsOf(alice), expectedPower);
    }

    function test_Lock_Tier3() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 3);

        uint256 expectedPower = (LOCK_AMOUNT * 40000) / MULTIPLIER_BASE;
        assertEq(escrow.votingUnitsOf(alice), expectedPower);
    }

    function test_Lock_TransfersTokens() public {
        uint256 balBefore = token.balanceOf(alice);

        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        assertEq(token.balanceOf(alice), balBefore - LOCK_AMOUNT);
        assertEq(token.balanceOf(address(escrow)), LOCK_AMOUNT);
    }

    function test_Lock_UpdatesTotalLocked() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        assertEq(escrow.totalLocked(), LOCK_AMOUNT);

        vm.prank(bob);
        escrow.lock(LOCK_AMOUNT * 2, 1);

        assertEq(escrow.totalLocked(), LOCK_AMOUNT * 3);
    }

    function test_Lock_EmitsEvent() public {
        uint64 expectedUnlock = uint64(block.timestamp) + 180 days;

        vm.expectEmit(true, false, false, true);
        emit VotingEscrow.Locked(alice, LOCK_AMOUNT, 0, expectedUnlock);

        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);
    }

    function test_RevertLock_ZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.ZeroAmount.selector);
        escrow.lock(0, 0);
    }

    function test_RevertLock_InvalidTier() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidTier.selector, 4));
        escrow.lock(LOCK_AMOUNT, 4);
    }

    function test_RevertLock_AlreadyLocked() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        vm.prank(alice);
        vm.expectRevert(VotingEscrow.AlreadyLocked.selector);
        escrow.lock(LOCK_AMOUNT, 1);
    }

    // ===== ExtendLock Tests =====

    function test_ExtendLock() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        uint256 oldPower = escrow.votingUnitsOf(alice);

        vm.prank(alice);
        escrow.extendLock(2);

        (, uint64 newUnlock, uint8 newTier) = escrow.locks(alice);
        assertEq(newTier, 2);
        assertEq(newUnlock, uint64(block.timestamp) + 730 days);

        uint256 newPower = escrow.votingUnitsOf(alice);
        uint256 expectedPower = (LOCK_AMOUNT * 30000) / MULTIPLIER_BASE;
        assertEq(newPower, expectedPower);
        assertGt(newPower, oldPower);
    }

    function test_ExtendLock_EmitsEvent() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        uint64 expectedUnlock = uint64(block.timestamp) + 730 days;

        vm.expectEmit(true, false, false, true);
        emit VotingEscrow.LockExtended(alice, 0, 2, expectedUnlock);

        vm.prank(alice);
        escrow.extendLock(2);
    }

    function test_RevertExtendLock_NotLocked() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.NotLocked.selector);
        escrow.extendLock(1);
    }

    function test_RevertExtendLock_InvalidTier() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidTier.selector, 4));
        escrow.extendLock(4);
    }

    function test_RevertExtendLock_SameTier() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.CannotReduceTier.selector, 1, 1));
        escrow.extendLock(1);
    }

    function test_RevertExtendLock_LowerTier() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 2);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.CannotReduceTier.selector, 2, 1));
        escrow.extendLock(1);
    }

    // ===== Withdraw Tests =====

    function test_Withdraw() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        // Warp past unlock
        vm.warp(block.timestamp + 180 days);

        uint256 balBefore = token.balanceOf(alice);

        vm.prank(alice);
        escrow.withdraw();

        assertEq(token.balanceOf(alice), balBefore + LOCK_AMOUNT);
        assertEq(escrow.votingUnitsOf(alice), 0);
        assertEq(escrow.totalLocked(), 0);

        (uint128 amount, , ) = escrow.locks(alice);
        assertEq(amount, 0);
    }

    function test_Withdraw_EmitsEvent() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        vm.warp(block.timestamp + 180 days);

        vm.expectEmit(true, false, false, true);
        emit VotingEscrow.Withdrawn(alice, LOCK_AMOUNT);

        vm.prank(alice);
        escrow.withdraw();
    }

    function test_RevertWithdraw_NotLocked() public {
        vm.prank(alice);
        vm.expectRevert(VotingEscrow.NotLocked.selector);
        escrow.withdraw();
    }

    function test_RevertWithdraw_LockNotExpired() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        vm.warp(block.timestamp + 179 days);

        vm.prank(alice);
        vm.expectRevert();
        escrow.withdraw();
    }

    // ===== Delegation Tests =====

    function test_Delegation_SelfDelegate() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 1);

        // No votes until delegated
        assertEq(escrow.getVotes(alice), 0);

        vm.prank(alice);
        escrow.delegate(alice);

        uint256 expectedPower = (LOCK_AMOUNT * 20000) / MULTIPLIER_BASE;
        assertEq(escrow.getVotes(alice), expectedPower);
    }

    function test_Delegation_DelegateToOther() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 1);

        vm.prank(alice);
        escrow.delegate(bob);

        uint256 expectedPower = (LOCK_AMOUNT * 20000) / MULTIPLIER_BASE;
        assertEq(escrow.getVotes(bob), expectedPower);
        assertEq(escrow.getVotes(alice), 0);
    }

    function test_Delegation_Checkpoint() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 1);

        vm.prank(alice);
        escrow.delegate(alice);

        uint256 expectedPower = (LOCK_AMOUNT * 20000) / MULTIPLIER_BASE;
        uint256 snapshot = block.timestamp;

        // Advance time
        vm.warp(block.timestamp + 1 days);

        // Historical votes should still work
        assertEq(escrow.getPastVotes(alice, snapshot), expectedPower);
    }

    function test_Delegation_WithdrawBurnsVotes() public {
        vm.prank(alice);
        escrow.lock(LOCK_AMOUNT, 0);

        vm.prank(alice);
        escrow.delegate(alice);

        assertGt(escrow.getVotes(alice), 0);

        vm.warp(block.timestamp + 180 days);

        vm.prank(alice);
        escrow.withdraw();

        assertEq(escrow.getVotes(alice), 0);
    }

    // ===== Clock Tests =====

    function test_ClockMode() public view {
        assertEq(escrow.CLOCK_MODE(), "mode=timestamp");
    }

    function test_Clock() public view {
        assertEq(escrow.clock(), uint48(block.timestamp));
    }

    // ===== View Helpers =====

    function test_PreviewVotingPower() public view {
        uint256 amount = 1_000_000 * 10 ** 18;

        assertEq(escrow.previewVotingPower(amount, 0), (amount * 15000) / MULTIPLIER_BASE);
        assertEq(escrow.previewVotingPower(amount, 1), (amount * 20000) / MULTIPLIER_BASE);
        assertEq(escrow.previewVotingPower(amount, 2), (amount * 30000) / MULTIPLIER_BASE);
        assertEq(escrow.previewVotingPower(amount, 3), (amount * 40000) / MULTIPLIER_BASE);
    }

    function test_RevertPreviewVotingPower_InvalidTier() public {
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidTier.selector, 4));
        escrow.previewVotingPower(1000, 4);
    }

    // ===== Fuzz Tests =====

    function testFuzz_Lock(uint256 amount, uint8 tier) public {
        amount = bound(amount, 1, 10_000_000 * 10 ** 18);
        tier = uint8(bound(tier, 0, 3));

        vm.prank(alice);
        escrow.lock(amount, tier);

        uint256 multiplier = escrow.MULTIPLIERS(tier);
        uint256 expectedPower = (amount * multiplier) / MULTIPLIER_BASE;

        assertEq(escrow.votingUnitsOf(alice), expectedPower);
        assertEq(escrow.totalLocked(), amount);
    }

    function testFuzz_VotingPowerIncreasesByTier(uint256 amount) public {
        amount = bound(amount, 1 ether, 10_000_000 * 10 ** 18);

        uint256 power0 = escrow.previewVotingPower(amount, 0);
        uint256 power1 = escrow.previewVotingPower(amount, 1);
        uint256 power2 = escrow.previewVotingPower(amount, 2);
        uint256 power3 = escrow.previewVotingPower(amount, 3);

        assertLt(power0, power1);
        assertLt(power1, power2);
        assertLt(power2, power3);
    }
}
