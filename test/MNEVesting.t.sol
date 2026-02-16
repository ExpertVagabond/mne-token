// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MNEToken} from "../src/MNEToken.sol";
import {MNEVesting} from "../src/MNEVesting.sol";

contract MNEVestingTest is Test {
    MNEToken public token;
    MNEVesting public vesting;

    address public owner = address(this);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC);

    uint64 public tgeTime = 1_700_000_000; // arbitrary TGE timestamp
    uint64 public cliffDuration = 365 days; // 12 months
    uint64 public vestingDuration = 1095 days; // 36 months (~3 years)

    uint256 public aliceAllocation = 100_000_000 * 10 ** 18;
    uint256 public bobAllocation = 50_000_000 * 10 ** 18;

    function setUp() public {
        token = new MNEToken();
        vesting = new MNEVesting(address(token), tgeTime, cliffDuration, vestingDuration, owner);
    }

    // ===== Setup Phase Tests =====

    function test_ImmutableParams() public view {
        assertEq(address(vesting.TOKEN()), address(token));
        assertEq(vesting.START(), tgeTime);
        assertEq(vesting.CLIFF_DURATION(), cliffDuration);
        assertEq(vesting.VESTING_DURATION(), vestingDuration);
    }

    function test_AddBeneficiaries() public {
        address[] memory addrs = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        addrs[0] = alice;
        addrs[1] = bob;
        amounts[0] = aliceAllocation;
        amounts[1] = bobAllocation;

        vesting.addBeneficiaries(addrs, amounts);

        assertEq(vesting.allocations(alice), aliceAllocation);
        assertEq(vesting.allocations(bob), bobAllocation);
        assertEq(vesting.totalAllocated(), aliceAllocation + bobAllocation);
    }

    function test_RevertAddBeneficiaries_ZeroAddress() public {
        address[] memory addrs = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        addrs[0] = address(0);
        amounts[0] = 1000;

        vm.expectRevert(MNEVesting.ZeroAddress.selector);
        vesting.addBeneficiaries(addrs, amounts);
    }

    function test_RevertAddBeneficiaries_ZeroAmount() public {
        address[] memory addrs = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        addrs[0] = alice;
        amounts[0] = 0;

        vm.expectRevert(MNEVesting.ZeroAmount.selector);
        vesting.addBeneficiaries(addrs, amounts);
    }

    function test_RevertAddBeneficiaries_DuplicateBeneficiary() public {
        address[] memory addrs = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        addrs[0] = alice;
        amounts[0] = aliceAllocation;

        vesting.addBeneficiaries(addrs, amounts);

        vm.expectRevert(abi.encodeWithSelector(MNEVesting.BeneficiaryExists.selector, alice));
        vesting.addBeneficiaries(addrs, amounts);
    }

    function test_RevertAddBeneficiaries_ArrayMismatch() public {
        address[] memory addrs = new address[](2);
        uint256[] memory amounts = new uint256[](1);
        addrs[0] = alice;
        addrs[1] = bob;
        amounts[0] = aliceAllocation;

        vm.expectRevert(MNEVesting.ArrayLengthMismatch.selector);
        vesting.addBeneficiaries(addrs, amounts);
    }

    function test_RevertAddBeneficiaries_NotOwner() public {
        address[] memory addrs = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        addrs[0] = alice;
        amounts[0] = aliceAllocation;

        vm.prank(alice);
        vm.expectRevert();
        vesting.addBeneficiaries(addrs, amounts);
    }

    function test_RevertAddBeneficiaries_AfterFinalize() public {
        _setupAndFinalize();

        address[] memory addrs = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        addrs[0] = charlie;
        amounts[0] = 1000;

        vm.expectRevert(MNEVesting.AlreadyFinalized.selector);
        vesting.addBeneficiaries(addrs, amounts);
    }

    // ===== Finalize Tests =====

    function test_Finalize() public {
        _addBeneficiaries();
        token.transfer(address(vesting), aliceAllocation + bobAllocation);

        vesting.finalize();

        assertTrue(vesting.finalized());
    }

    function test_RevertFinalize_InsufficientBalance() public {
        _addBeneficiaries();
        // Don't transfer tokens

        vm.expectRevert(
            abi.encodeWithSelector(MNEVesting.InsufficientBalance.selector, aliceAllocation + bobAllocation, 0)
        );
        vesting.finalize();
    }

    function test_RevertFinalize_AlreadyFinalized() public {
        _setupAndFinalize();

        vm.expectRevert(MNEVesting.AlreadyFinalized.selector);
        vesting.finalize();
    }

    // ===== Vesting Schedule Tests =====

    function test_VestedAmount_BeforeCliff() public {
        _setupAndFinalize();

        // At TGE - still in cliff
        assertEq(vesting.vestedAmount(alice, tgeTime), 0);

        // 1 day before cliff end
        assertEq(vesting.vestedAmount(alice, tgeTime + cliffDuration - 1 days), 0);
    }

    function test_VestedAmount_AtCliffEnd() public {
        _setupAndFinalize();

        // Exactly at cliff end — 0% of linear vesting elapsed
        uint64 cliffEnd = tgeTime + cliffDuration;
        assertEq(vesting.vestedAmount(alice, cliffEnd), 0);
    }

    function test_VestedAmount_MidVesting() public {
        _setupAndFinalize();

        uint64 cliffEnd = tgeTime + cliffDuration;
        // Halfway through vesting
        uint64 midpoint = cliffEnd + vestingDuration / 2;

        uint256 expected = aliceAllocation / 2;
        assertEq(vesting.vestedAmount(alice, midpoint), expected);
    }

    function test_VestedAmount_EndOfVesting() public {
        _setupAndFinalize();

        uint64 vestEnd = tgeTime + cliffDuration + vestingDuration;
        assertEq(vesting.vestedAmount(alice, vestEnd), aliceAllocation);
    }

    function test_VestedAmount_AfterVesting() public {
        _setupAndFinalize();

        uint64 wayAfter = tgeTime + cliffDuration + vestingDuration + 365 days;
        assertEq(vesting.vestedAmount(alice, wayAfter), aliceAllocation);
    }

    function test_VestedAmount_NonBeneficiary() public view {
        assertEq(vesting.vestedAmount(charlie, tgeTime + cliffDuration + vestingDuration), 0);
    }

    // ===== Release Tests =====

    function test_Release_MidVesting() public {
        _setupAndFinalize();

        uint64 cliffEnd = tgeTime + cliffDuration;
        uint64 midpoint = cliffEnd + vestingDuration / 2;
        vm.warp(midpoint);

        uint256 expectedRelease = aliceAllocation / 2;

        vm.prank(alice);
        vesting.release();

        assertEq(token.balanceOf(alice), expectedRelease);
        assertEq(vesting.released(alice), expectedRelease);
    }

    function test_Release_FullVesting() public {
        _setupAndFinalize();

        uint64 vestEnd = tgeTime + cliffDuration + vestingDuration;
        vm.warp(vestEnd);

        vm.prank(alice);
        vesting.release();

        assertEq(token.balanceOf(alice), aliceAllocation);
        assertEq(vesting.released(alice), aliceAllocation);
    }

    function test_Release_MultipleReleases() public {
        _setupAndFinalize();

        uint64 cliffEnd = tgeTime + cliffDuration;

        // Release at 25%
        vm.warp(cliffEnd + vestingDuration / 4);
        vm.prank(alice);
        vesting.release();
        uint256 first = token.balanceOf(alice);
        assertEq(first, aliceAllocation / 4);

        // Release at 75%
        vm.warp(cliffEnd + (vestingDuration * 3) / 4);
        vm.prank(alice);
        vesting.release();
        uint256 second = token.balanceOf(alice);
        assertEq(second, (aliceAllocation * 3) / 4);

        // Release at 100%
        vm.warp(cliffEnd + vestingDuration);
        vm.prank(alice);
        vesting.release();
        assertEq(token.balanceOf(alice), aliceAllocation);
    }

    function test_RevertRelease_BeforeFinalize() public {
        _addBeneficiaries();

        vm.prank(alice);
        vm.expectRevert(MNEVesting.NotFinalized.selector);
        vesting.release();
    }

    function test_RevertRelease_NotBeneficiary() public {
        _setupAndFinalize();

        vm.warp(tgeTime + cliffDuration + vestingDuration);
        vm.prank(charlie);
        vm.expectRevert(MNEVesting.NotBeneficiary.selector);
        vesting.release();
    }

    function test_RevertRelease_NothingToRelease() public {
        _setupAndFinalize();

        // Still in cliff period
        vm.warp(tgeTime + cliffDuration - 1);
        vm.prank(alice);
        vm.expectRevert(MNEVesting.NothingToRelease.selector);
        vesting.release();
    }

    function test_RevertRelease_AlreadyClaimedAll() public {
        _setupAndFinalize();

        vm.warp(tgeTime + cliffDuration + vestingDuration);
        vm.prank(alice);
        vesting.release();

        // Try to release again — nothing left
        vm.prank(alice);
        vm.expectRevert(MNEVesting.NothingToRelease.selector);
        vesting.release();
    }

    // ===== Releasable View Tests =====

    function test_Releasable() public {
        _setupAndFinalize();

        uint64 cliffEnd = tgeTime + cliffDuration;
        vm.warp(cliffEnd + vestingDuration / 2);

        assertEq(vesting.releasable(alice), aliceAllocation / 2);
    }

    function test_Releasable_AfterPartialRelease() public {
        _setupAndFinalize();

        uint64 cliffEnd = tgeTime + cliffDuration;

        // Release at 25%
        vm.warp(cliffEnd + vestingDuration / 4);
        vm.prank(alice);
        vesting.release();

        // Check releasable at 50%
        vm.warp(cliffEnd + vestingDuration / 2);
        assertEq(vesting.releasable(alice), aliceAllocation / 4);
    }

    // ===== Zero Vesting Duration (cliff-only) =====

    function test_ZeroVestingDuration_FullyVestedAfterCliff() public {
        // Community TGE: cliff only, no linear vesting
        MNEVesting cliffOnly = new MNEVesting(address(token), tgeTime, 60 days, 0, owner);

        address[] memory addrs = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        addrs[0] = alice;
        amounts[0] = 10_000_000 * 10 ** 18;

        cliffOnly.addBeneficiaries(addrs, amounts);
        token.transfer(address(cliffOnly), 10_000_000 * 10 ** 18);
        cliffOnly.finalize();

        // Before cliff
        vm.warp(tgeTime + 59 days);
        assertEq(cliffOnly.releasable(alice), 0);

        // After cliff — fully vested
        vm.warp(tgeTime + 60 days);
        assertEq(cliffOnly.releasable(alice), 10_000_000 * 10 ** 18);
    }

    // ===== Fuzz Tests =====

    function testFuzz_VestedAmountNeverExceedsAllocation(uint64 timestamp) public {
        _setupAndFinalize();

        uint256 vested = vesting.vestedAmount(alice, timestamp);
        assertLe(vested, aliceAllocation);
    }

    function testFuzz_VestedAmountMonotonicallyIncreasing(uint64 t1, uint64 t2) public {
        _setupAndFinalize();
        vm.assume(t1 <= t2);

        uint256 vested1 = vesting.vestedAmount(alice, t1);
        uint256 vested2 = vesting.vestedAmount(alice, t2);
        assertGe(vested2, vested1);
    }

    // ===== Multiple Beneficiaries =====

    function test_MultipleBeneficiaries_IndependentReleases() public {
        _setupAndFinalize();

        uint64 cliffEnd = tgeTime + cliffDuration;
        vm.warp(cliffEnd + vestingDuration);

        vm.prank(alice);
        vesting.release();
        assertEq(token.balanceOf(alice), aliceAllocation);

        vm.prank(bob);
        vesting.release();
        assertEq(token.balanceOf(bob), bobAllocation);
    }

    // ===== Helpers =====

    function _addBeneficiaries() internal {
        address[] memory addrs = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        addrs[0] = alice;
        addrs[1] = bob;
        amounts[0] = aliceAllocation;
        amounts[1] = bobAllocation;

        vesting.addBeneficiaries(addrs, amounts);
    }

    function _setupAndFinalize() internal {
        _addBeneficiaries();
        token.transfer(address(vesting), aliceAllocation + bobAllocation);
        vesting.finalize();
    }
}
