# ERC20 Token Staking

**Inspired by a [BowTiedPickle](https://twitter.com/BowTiedPickle/status/1579306658928656385/photo/1) twitter post.**

## Setup

- Install [Foundry](https://github.com/foundry-rs/foundry).
- To run the all tests, in CL enter:

```sh
forge test
```

- To run a specific test (with stack and setup traces displayed):

```sh
forge test --match-contract [CONTRACT_NAME_HERE] --match-test [TEST_NAME_HERE] -vvvvv
```

## Exercise Description

Problem specifications are as follows:

- Owner can fund with an ERC-20 reward token and define a total reward rate.
- Users can stake an ERC-20 staking token at any time.
- Users receive rewards (denominated in reward token) proportional to their staked portion of the pool.
- Users can withdraw at any time.
- Users can claim rewards at any time.

## Testing Coverage

## Acknowledgements

When I found myself feeling stuck, I referred to the following contracts:

- `ERC20StakingPool.sol` from ZeframLou's Playpen ([here](https://github.com/ZeframLou/playpen/blob/main/src/ERC20StakingPool.sol)).
- Staking Rewards from Solidity By Example ([here](https://solidity-by-example.org/defi/staking-rewards/)).
