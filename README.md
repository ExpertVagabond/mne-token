<div align="center">

# MNE Token

**Monee governance token and vesting contracts -- ERC-20, Solidity 0.8.24, OpenZeppelin v5**

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?logo=solidity&logoColor=white)](https://soliditylang.org)
[![Foundry](https://img.shields.io/badge/Foundry-Forge-orange)](https://book.getfoundry.sh)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-v5-4E5EE4?logo=openzeppelin&logoColor=white)](https://openzeppelin.com)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Overview

MNE is the governance token for the Monee ecosystem. Fixed supply of 7 billion tokens minted at deployment with no mint, burn, or upgrade functions. The suite includes vesting schedules, vote-escrowed governance (veMNE), an on-chain governor with timelock, and an ecosystem treasury.

## Contracts

| Contract | Description |
|----------|-------------|
| **MNEToken** | ERC-20 + ERC-2612 Permit. Fixed 7B supply, immutable. |
| **MNEVesting** | Multi-beneficiary cliff + linear vesting. Immutable after finalization. |
| **VotingEscrow** | Vote-escrowed MNE (veMNE). Lock tokens for 1 week to 4 years for governance power. |
| **MNEGovernor** | On-chain governance with proposal lifecycle, quorum, and timelock execution. |
| **MNEEcosystemTreasury** | Multi-asset treasury with spending limits, cooldowns, and emergency controls. |

## Architecture

```
MNEToken (ERC-20, 7B fixed supply)
    |
    +-- MNEVesting (cliff + linear unlock per category)
    |
    +-- VotingEscrow (veMNE -- lock MNE for governance weight)
    |       |
    |       +-- MNEGovernor (proposals, voting, timelock execution)
    |
    +-- MNEEcosystemTreasury (controlled spending, emergency pause)
```

## Quick Start

```bash
# Clone
git clone https://github.com/ExpertVagabond/mne-token.git
cd mne-token

# Install dependencies
npm install
forge install

# Compile
forge build

# Run tests
forge test -vvv

# Format
forge fmt
```

## Token Details

| Property | Value |
|----------|-------|
| Name | Monee |
| Symbol | MNE |
| Decimals | 18 |
| Total Supply | 7,000,000,000 MNE |
| Standard | ERC-20 + ERC-2612 (Permit) |
| Solidity | 0.8.24 |
| Framework | Foundry + Hardhat |

## Governance

The governance system uses vote-escrowed tokens (veMNE) for voting power:

1. **Lock MNE** into VotingEscrow for 1 week to 4 years
2. **Voting power** scales linearly with lock duration
3. **Propose** changes via MNEGovernor (minimum threshold required)
4. **Vote** during the voting period (quorum: 4% of total supply)
5. **Execute** through timelock after voting succeeds

## Vesting

Each vesting contract is deployed per allocation category (team, advisors, ecosystem, etc.):

- **Cliff period** -- no tokens released until cliff ends
- **Linear vesting** -- tokens unlock linearly after cliff
- **Immutable** -- once finalized, no beneficiaries can be added or removed
- **Revocable** -- owner can revoke unvested tokens before finalization

## Treasury

The ecosystem treasury manages protocol-owned assets:

- **Spending limits** -- per-token daily caps
- **Cooldown periods** -- minimum time between withdrawals
- **Multi-asset** -- supports ETH and any ERC-20 token
- **Emergency controls** -- pause all operations instantly

## Testing

All contracts have comprehensive Foundry test suites:

```bash
# Run all tests
forge test -vvv

# Run specific test file
forge test --match-path test/MNEToken.t.sol -vvv

# Gas report
forge test --gas-report
```

## Security

- No mint or burn functions on the base token
- Two-step ownership transfers (Ownable2Step)
- Immutable vesting after finalization
- Timelock on all governance actions
- OpenZeppelin v5 battle-tested implementations

## License

[MIT](LICENSE)
