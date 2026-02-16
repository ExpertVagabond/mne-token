// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MNEToken} from "../src/MNEToken.sol";
import {MNEEcosystemTreasury} from "../src/MNEEcosystemTreasury.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";
import {MNEGovernor} from "../src/MNEGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

/// @notice End-to-end integration test: Lock MNE → Delegate → Propose → Vote → Queue → Execute
contract GovernanceIntegrationTest is Test {
    MNEToken public token;
    MNEEcosystemTreasury public treasury;
    VotingEscrow public escrow;
    MNEGovernor public governor;
    TimelockController public timelock;

    address public deployer = address(this);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC);
    address public recipient = address(0xBEEF);

    uint256 public constant TREASURY_AMOUNT = 3_710_000_000 * 10 ** 18;

    function setUp() public {
        token = new MNEToken();

        // Deploy timelock
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        timelock = new TimelockController(2 days, proposers, executors, deployer);

        // Deploy escrow and governor
        escrow = new VotingEscrow(address(token));
        governor = new MNEGovernor(escrow, timelock, token);

        // Wire up roles
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // Deploy treasury and transfer ownership to timelock
        treasury = new MNEEcosystemTreasury(address(token), deployer);
        token.transfer(address(treasury), TREASURY_AMOUNT);

        // Transfer treasury ownership to timelock
        treasury.transferOwnership(address(timelock));
        vm.prank(address(timelock));
        treasury.acceptOwnership();

        // Fund voters
        token.transfer(alice, 500_000_000 * 10 ** 18);
        token.transfer(bob, 200_000_000 * 10 ** 18);
        token.transfer(charlie, 100_000_000 * 10 ** 18);

        // All lock and delegate
        _lockAndDelegate(alice, 500_000_000 * 10 ** 18, 3); // 4x = 2B veMNE
        _lockAndDelegate(bob, 200_000_000 * 10 ** 18, 2);   // 3x = 600M veMNE
        _lockAndDelegate(charlie, 100_000_000 * 10 ** 18, 1); // 2x = 200M veMNE

        // Advance 1 second so checkpoints register
        vm.warp(block.timestamp + 1);
    }

    // ===== Full E2E: Governance releases tokens from treasury =====

    function test_E2E_TreasuryRelease() public {
        uint256 releaseAmount = 10_000_000 * 10 ** 18;

        // Build proposal: treasury.release(recipient, releaseAmount)
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeWithSelector(treasury.release.selector, recipient, releaseAmount);
        string memory description = "Release 10M MNE to recipient";

        // 1. Propose
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, description);

        // 2. Advance past voting delay
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        // 3. Vote: alice For, bob For, charlie Abstain
        vm.prank(alice);
        governor.castVote(proposalId, 1); // For

        vm.prank(bob);
        governor.castVote(proposalId, 1); // For

        vm.prank(charlie);
        governor.castVote(proposalId, 2); // Abstain

        // 4. Advance past voting period
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        // Verify succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // 5. Queue
        bytes32 descHash = keccak256(bytes(description));
        governor.queue(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // 6. Wait 48 hours
        vm.warp(block.timestamp + 2 days + 1);

        // 7. Execute
        governor.execute(targets, values, calldatas, descHash);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));

        // 8. Verify funds moved
        assertEq(token.balanceOf(recipient), releaseAmount);
        assertEq(treasury.balance(), TREASURY_AMOUNT - releaseAmount);
    }

    // ===== Proposal fails if quorum not met =====

    function test_E2E_QuorumNotMet() public {
        // Only charlie votes (60M veMNE), quorum is 12% of EVS (~828M)
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeWithSelector(treasury.release.selector, recipient, 1000);

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Small release");

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        // Only charlie votes
        vm.prank(charlie);
        governor.castVote(proposalId, 1);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        // Should be defeated (quorum not met)
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // ===== Proposal fails if more Against =====

    function test_E2E_Defeated_MoreAgainst() public {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(treasury);
        calldatas[0] = abi.encodeWithSelector(treasury.release.selector, recipient, 1000);

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Controversial release");

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        // Bob and Charlie vote For (150M + 60M = 210M)
        vm.prank(bob);
        governor.castVote(proposalId, 1);
        vm.prank(charlie);
        governor.castVote(proposalId, 1);

        // Alice votes Against (400M > 210M)
        vm.prank(alice);
        governor.castVote(proposalId, 0);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // ===== Multiple voters with different lock tiers =====

    function test_E2E_DifferentTierVotingPower() public {
        // Verify voting power reflects tier multipliers
        uint256 alicePower = escrow.getVotes(alice);
        uint256 bobPower = escrow.getVotes(bob);
        uint256 charliePower = escrow.getVotes(charlie);

        // alice: 500M * 4x = 2B
        assertEq(alicePower, (500_000_000 * 10 ** 18 * 40000) / 10000);
        // bob: 200M * 3x = 600M
        assertEq(bobPower, (200_000_000 * 10 ** 18 * 30000) / 10000);
        // charlie: 100M * 2x = 200M
        assertEq(charliePower, (100_000_000 * 10 ** 18 * 20000) / 10000);
    }

    // ===== Treasury ownership is timelock =====

    function test_TreasuryOwnedByTimelock() public view {
        assertEq(treasury.owner(), address(timelock));
    }

    function test_RevertDirectTreasuryRelease() public {
        // Cannot release directly — must go through governance
        vm.prank(alice);
        vm.expectRevert();
        treasury.release(recipient, 1000);
    }

    // ===== Helpers =====

    function _lockAndDelegate(address user, uint256 amount, uint8 tier) internal {
        vm.startPrank(user);
        token.approve(address(escrow), type(uint256).max);
        escrow.lock(amount, tier);
        escrow.delegate(user);
        vm.stopPrank();
    }
}
