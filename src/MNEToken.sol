// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title MNE Token — Monee Governance Token
/// @notice Fixed-supply ERC-20 governance token. 7,000,000,000 MNE minted at deployment.
///         No mint, burn, or upgrade functions exist.
contract MNEToken is ERC20, ERC20Permit {
    uint256 public constant TOTAL_SUPPLY = 7_000_000_000 * 10 ** 18;

    constructor() ERC20("Monee", "MNE") ERC20Permit("Monee") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    function nonces(address owner) public view override(ERC20Permit) returns (uint256) {
        return super.nonces(owner);
    }
}
