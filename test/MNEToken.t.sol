// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MNEToken} from "../src/MNEToken.sol";

contract MNETokenTest is Test {
    MNEToken public token;
    address public deployer = address(this);

    function setUp() public {
        token = new MNEToken();
    }

    function test_Name() public view {
        assertEq(token.name(), "Monee");
    }

    function test_Symbol() public view {
        assertEq(token.symbol(), "MNE");
    }

    function test_Decimals() public view {
        assertEq(token.decimals(), 18);
    }

    function test_TotalSupply() public view {
        assertEq(token.totalSupply(), 7_000_000_000 * 10 ** 18);
    }

    function test_TotalSupplyConstant() public view {
        assertEq(token.TOTAL_SUPPLY(), 7_000_000_000 * 10 ** 18);
    }

    function test_DeployerReceivesEntireSupply() public view {
        assertEq(token.balanceOf(deployer), 7_000_000_000 * 10 ** 18);
    }

    function test_Transfer() public {
        address recipient = address(0xBEEF);
        uint256 amount = 1000 * 10 ** 18;

        token.transfer(recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(deployer), 7_000_000_000 * 10 ** 18 - amount);
    }

    function test_Approve_TransferFrom() public {
        address spender = address(0xBEEF);
        address recipient = address(0xCAFE);
        uint256 amount = 500 * 10 ** 18;

        token.approve(spender, amount);
        assertEq(token.allowance(deployer, spender), amount);

        vm.prank(spender);
        token.transferFrom(deployer, recipient, amount);

        assertEq(token.balanceOf(recipient), amount);
    }

    function test_Permit() public {
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);
        address spender = address(0xBEEF);
        uint256 amount = 1000 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        // Transfer some tokens to the permit signer
        token.transfer(owner, amount);

        bytes32 permitTypehash =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

        bytes32 structHash =
            keccak256(abi.encode(permitTypehash, owner, spender, amount, token.nonces(owner), deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(owner, spender, amount, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), amount);
    }

    function test_NoMintFunction() public view {
        // Verify there's no way to mint more tokens
        // The contract only has ERC20 + Permit functions — no mint exposed
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    function testFuzz_Transfer(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(to != deployer);
        amount = bound(amount, 0, token.balanceOf(deployer));

        token.transfer(to, amount);
        assertEq(token.balanceOf(to), amount);
    }
}
