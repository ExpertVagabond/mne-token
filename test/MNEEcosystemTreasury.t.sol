// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MNEToken} from "../src/MNEToken.sol";
import {MNEEcosystemTreasury} from "../src/MNEEcosystemTreasury.sol";

contract MNEEcosystemTreasuryTest is Test {
    MNEToken public token;
    MNEEcosystemTreasury public treasury;

    address public owner = address(this);
    address public recipient = address(0xBEEF);
    uint256 public treasuryAmount = 3_710_000_000 * 10 ** 18; // 53%

    function setUp() public {
        token = new MNEToken();
        treasury = new MNEEcosystemTreasury(address(token), owner);
        token.transfer(address(treasury), treasuryAmount);
    }

    function test_Balance() public view {
        assertEq(treasury.balance(), treasuryAmount);
    }

    function test_Release() public {
        uint256 amount = 1_000_000 * 10 ** 18;

        treasury.release(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(treasury.balance(), treasuryAmount - amount);
    }

    function test_RevertRelease_NotOwner() public {
        vm.prank(recipient);
        vm.expectRevert();
        treasury.release(recipient, 1000);
    }

    function test_RevertRelease_ZeroAddress() public {
        vm.expectRevert(MNEEcosystemTreasury.ZeroAddress.selector);
        treasury.release(address(0), 1000);
    }

    function test_RevertRelease_ZeroAmount() public {
        vm.expectRevert(MNEEcosystemTreasury.ZeroAmount.selector);
        treasury.release(recipient, 0);
    }

    function test_RevertRelease_InsufficientBalance() public {
        uint256 tooMuch = treasuryAmount + 1;
        vm.expectRevert(abi.encodeWithSelector(MNEEcosystemTreasury.InsufficientBalance.selector, tooMuch, treasuryAmount));
        treasury.release(recipient, tooMuch);
    }

    function test_OwnershipTransfer() public {
        address newOwner = address(0xCAFE);

        treasury.transferOwnership(newOwner);
        assertEq(treasury.pendingOwner(), newOwner);

        vm.prank(newOwner);
        treasury.acceptOwnership();
        assertEq(treasury.owner(), newOwner);

        // New owner can release
        vm.prank(newOwner);
        treasury.release(recipient, 1000);
        assertEq(token.balanceOf(recipient), 1000);
    }

    function testFuzz_Release(uint256 amount) public {
        amount = bound(amount, 1, treasuryAmount);

        treasury.release(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(treasury.balance(), treasuryAmount - amount);
    }
}
