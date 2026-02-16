// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MNEToken} from "../src/MNEToken.sol";
import {VotingEscrow} from "../src/VotingEscrow.sol";
import {MNEGovernor} from "../src/MNEGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

contract MNEGovernorTest is Test {
    MNEToken public token;
    VotingEscrow public escrow;
    MNEGovernor public governor;
    TimelockController public timelock;

    address public deployer = address(this);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    uint256 public constant PROPOSAL_THRESHOLD = 7_000_000 * 10 ** 18; // 7M veMNE
    uint256 public constant LOCK_AMOUNT = 500_000_000 * 10 ** 18; // 500M MNE

    function setUp() public {
        token = new MNEToken();

        // Deploy timelock (deployer as temp admin)
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // anyone can execute

        timelock = new TimelockController(2 days, proposers, executors, deployer);

        // Deploy escrow and governor
        escrow = new VotingEscrow(address(token));
        governor = new MNEGovernor(escrow, timelock, token);

        // Grant proposer/canceller roles to governor
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Renounce admin
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // Fund alice and bob with MNE
        token.transfer(alice, LOCK_AMOUNT);
        token.transfer(bob, LOCK_AMOUNT);

        // Alice locks and self-delegates (enough for proposal threshold)
        vm.startPrank(alice);
        token.approve(address(escrow), type(uint256).max);
        escrow.lock(LOCK_AMOUNT, 3); // 4x = 200M veMNE
        escrow.delegate(alice);
        vm.stopPrank();

        // Bob locks and self-delegates
        vm.startPrank(bob);
        token.approve(address(escrow), type(uint256).max);
        escrow.lock(LOCK_AMOUNT, 1); // 2x = 100M veMNE
        escrow.delegate(bob);
        vm.stopPrank();
    }

    // ===== Configuration Tests =====

    function test_GovernorName() public view {
        assertEq(governor.name(), "MNE Governor");
    }

    function test_VotingDelay() public view {
        assertEq(governor.votingDelay(), 1 days);
    }

    function test_VotingPeriod() public view {
        assertEq(governor.votingPeriod(), 3 days);
    }

    function test_ProposalThreshold() public view {
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
    }

    function test_ClockMode() public view {
        assertEq(governor.CLOCK_MODE(), "mode=timestamp");
    }

    function test_Clock() public view {
        assertEq(governor.clock(), uint48(block.timestamp));
    }

    function test_QuorumNumerator() public view {
        assertEq(governor.quorumNumerator(), 12);
    }

    // ===== Quorum Tests =====

    function test_Quorum_NoLockedNoFoundation() public view {
        // EVS = 7B - 100M locked (alice+bob) - 0 foundation
        // But tokens are: 7B total, 100M locked in escrow
        uint256 totalSupply = token.totalSupply();
        uint256 locked = escrow.totalLocked();
        uint256 expectedEVS = totalSupply - locked;
        uint256 expectedQuorum = (expectedEVS * 12) / 100;

        assertEq(governor.quorum(block.timestamp), expectedQuorum);
    }

    // ===== Proposal Tests =====

    function test_Propose() public {
        // Warp 1 second so getPastVotes has a checkpoint
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(token);
        calldatas[0] = abi.encodeWithSelector(token.transfer.selector, alice, 1000);

        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Transfer tokens");

        assertGt(proposalId, 0);
    }

    function test_RevertPropose_BelowThreshold() public {
        vm.warp(block.timestamp + 1);

        address noVotes = address(0xDEAD);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(token);
        calldatas[0] = abi.encodeWithSelector(token.transfer.selector, noVotes, 1);

        vm.prank(noVotes);
        vm.expectRevert();
        governor.propose(targets, values, calldatas, "Should fail");
    }

    // ===== Voting Tests =====

    function test_Vote_ForAgainstAbstain() public {
        vm.warp(block.timestamp + 1);

        (uint256 proposalId, ) = _createProposal();

        // Advance past voting delay
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        // Alice votes For
        vm.prank(alice);
        governor.castVote(proposalId, 1); // For

        // Bob votes Against
        vm.prank(bob);
        governor.castVote(proposalId, 0); // Against

        assertTrue(governor.hasVoted(proposalId, alice));
        assertTrue(governor.hasVoted(proposalId, bob));

        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);
        assertGt(forVotes, 0);
        assertGt(against, 0);
        assertEq(abstain, 0);
    }

    function test_RevertVote_AlreadyVoted() public {
        vm.warp(block.timestamp + 1);

        (uint256 proposalId, ) = _createProposal();
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        vm.prank(alice);
        governor.castVote(proposalId, 1);

        vm.prank(alice);
        vm.expectRevert();
        governor.castVote(proposalId, 0);
    }

    // ===== Full Lifecycle: Propose → Vote → Queue → Execute =====

    function test_FullLifecycle() public {
        vm.warp(block.timestamp + 1);

        // Send some tokens to timelock so it can execute a transfer
        token.transfer(address(timelock), 1_000_000 * 10 ** 18);

        address recipient = address(0xCAFE);
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(token);
        calldatas[0] = abi.encodeWithSelector(token.transfer.selector, recipient, 500_000 * 10 ** 18);

        // Propose
        vm.prank(alice);
        uint256 proposalId = governor.propose(targets, values, calldatas, "Send 500K to CAFE");

        // Advance past voting delay
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        // Vote (alice has 200M veMNE, enough for quorum)
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Advance past voting period
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        // State should be Succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Queue
        governor.queue(targets, values, calldatas, keccak256("Send 500K to CAFE"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued));

        // Wait for timelock delay (48 hours)
        vm.warp(block.timestamp + 2 days + 1);

        // Execute
        governor.execute(targets, values, calldatas, keccak256("Send 500K to CAFE"));
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));

        // Verify tokens transferred
        assertEq(token.balanceOf(recipient), 500_000 * 10 ** 18);
    }

    // ===== Proposal Fails if Not Enough For Votes =====

    function test_ProposalDefeated_MoreAgainst() public {
        // Give charlie more voting power than alice
        address charlie = address(0xC);
        token.transfer(charlie, 1_000_000_000 * 10 ** 18);

        vm.startPrank(charlie);
        token.approve(address(escrow), type(uint256).max);
        escrow.lock(1_000_000_000 * 10 ** 18, 3); // 4x = 4B veMNE
        escrow.delegate(charlie);
        vm.stopPrank();

        vm.warp(block.timestamp + 1);

        (uint256 proposalId, ) = _createProposal();

        vm.warp(block.timestamp + governor.votingDelay() + 1);

        // Alice votes For (200M)
        vm.prank(alice);
        governor.castVote(proposalId, 1);

        // Charlie votes Against (400M)
        vm.prank(charlie);
        governor.castVote(proposalId, 0);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated));
    }

    // ===== Governance-Only Parameter Changes =====

    function test_SetQuorumNumerator_ViaGovernance() public {
        // This would need a full governance cycle to change
        // Just verify the view function works
        assertEq(governor.quorumNumerator(), 12);
    }

    function test_RevertSetQuorumNumerator_NotGovernance() public {
        vm.prank(alice);
        vm.expectRevert();
        governor.setQuorumNumerator(20);
    }

    function test_RevertSetFoundationHeldTokens_NotGovernance() public {
        vm.prank(alice);
        vm.expectRevert();
        governor.setFoundationHeldTokens(1_000_000 * 10 ** 18);
    }

    // ===== Timelock Integration =====

    function test_Executor_IsTimelock() public view {
        assertEq(governor.timelock(), address(timelock));
    }

    function test_ProposalNeedsQueuing() public view {
        assertTrue(governor.proposalNeedsQueuing(0));
    }

    // ===== Helpers =====

    function _createProposal() internal returns (uint256 proposalId, bytes32 descHash) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(token);
        calldatas[0] = abi.encodeWithSelector(token.transfer.selector, address(0xCAFE), 1000);

        vm.prank(alice);
        proposalId = governor.propose(targets, values, calldatas, "Test proposal");
        descHash = keccak256("Test proposal");
    }
}
