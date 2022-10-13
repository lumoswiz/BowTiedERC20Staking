// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import {ERC20StakingPool} from "../src/ERC20StakingPool.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Utilities} from "./utils/Utilities.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract ERC20StakingPoolTest is Test {
    uint256 internal constant STAKE_TOKEN_USER_BALANCE = 100e18;
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 1_000e18;
    uint256 internal constant DURATION = 7 days;

    Utilities internal utils;
    ERC20StakingPool internal pool;
    MockERC20 internal rewardToken;
    MockERC20 internal stakeToken;

    address payable internal poolOwner;
    address payable internal userA;
    address payable internal userB;

    function setUp() public {
        utils = new Utilities();

        // Create users
        address payable[] memory users = utils.createUsers(4);
        poolOwner = users[0];
        userA = users[1];
        userB = users[2];

        vm.label(poolOwner, "Pool Owner");
        vm.label(userA, "User A");
        vm.label(userB, "User B");
        vm.label(users[3], "Stake Token Deployer");

        vm.prank(users[3]);
        stakeToken = new MockERC20(TOKEN_INITIAL_SUPPLY);
        vm.label(address(stakeToken), "Staking Token");

        /// Gives users A and B 100 units of the stake token and adjusts the token's total supply
        deal(address(stakeToken), userA, STAKE_TOKEN_USER_BALANCE, true);
        deal(address(stakeToken), userB, STAKE_TOKEN_USER_BALANCE, true);
        assertEq(
            stakeToken.totalSupply(),
            2 * STAKE_TOKEN_USER_BALANCE + TOKEN_INITIAL_SUPPLY
        );
        assertEq(IERC20(stakeToken).balanceOf(userA), STAKE_TOKEN_USER_BALANCE);

        vm.startPrank(poolOwner);

        rewardToken = new MockERC20(TOKEN_INITIAL_SUPPLY);
        vm.label(address(rewardToken), "Reward Token");

        assertEq(
            IERC20(rewardToken).balanceOf(poolOwner),
            TOKEN_INITIAL_SUPPLY
        );

        pool = new ERC20StakingPool(
            address(rewardToken),
            address(stakeToken),
            DURATION
        );
        vm.label(address(pool), "ERC20 Staking Pool");

        vm.stopPrank();

        // Approvals
        vm.prank(userA);
        stakeToken.approve(address(pool), type(uint256).max);

        vm.prank(userB);
        stakeToken.approve(address(pool), type(uint256).max);
    }

    /// -----------------------------------------------------------------------
    /// Testing: `newRewardPeriod(uint256 rewardAmount)`
    /// -----------------------------------------------------------------------

    function testNewRewardPeriodRewardTokensAlreadyDeposited() public {
        uint256 REWARD_AMOUNT = 20e18;

        vm.startPrank(poolOwner);

        rewardToken.transfer(address(pool), REWARD_AMOUNT);
        pool.newRewardPeriod(REWARD_AMOUNT);

        vm.stopPrank();

        // updateTime properly set to block.timestamp
        assertEq(pool.updateTime(), block.timestamp);

        // endCurrentRewardPeriod properly set
        assertEq(
            pool.endCurrentRewardPeriod(),
            block.timestamp + pool.duration()
        );

        // rewardPerTokenStored should be 0 (storage var initialised to zero on deployment & no tokens staked currently)
        assertEq(pool.rewardPerTokenStored(), 0);

        // rewardRate properly set
        assertEq(pool.rewardRate(), REWARD_AMOUNT / pool.duration());
    }

    function testNewRewardPeriodWithNoRewardTokensInPool() public {
        uint256 REWARD_AMOUNT = 20e18;

        vm.prank(poolOwner);
        // No rewardTokens sent to pool before calling `newRewardPeriod`, expect revert.
        vm.expectRevert(
            ERC20StakingPool.Error_InsufficientRewardTokensInPool.selector
        );
        pool.newRewardPeriod(REWARD_AMOUNT);
    }

    /// -----------------------------------------------------------------------
    /// Testing: `stake(uint256 amount)`
    /// -----------------------------------------------------------------------
    function testStake() public {
        uint256 REWARD_AMOUNT = 20e18;
        fundAndStartNewRewardPeriod(REWARD_AMOUNT);

        uint256 poolBalanceBefore = stakeToken.balanceOf(address(pool));

        // User A stakes entire balance
        vm.startPrank(userA);
        uint256 amountStakedUserA = stakeToken.balanceOf(userA);
        pool.stake(amountStakedUserA);
        vm.stopPrank();

        // rewardPerTokenStored updated correctly
        assertEq(pool.rewardPerTokenStored(), pool.rewardPerToken());

        // Skip forward 4 days
        vm.warp(block.timestamp + 4 days);

        // User B stakes entire balance
        vm.startPrank(userB);
        uint256 amountStakedUserB = stakeToken.balanceOf(userB);
        pool.stake(amountStakedUserB);
        vm.stopPrank();

        // User balances reflect amounts staked
        assertEq(pool.balanceOfStaker(userA), amountStakedUserA);
        assertEq(pool.balanceOfStaker(userB), amountStakedUserB);

        // totalStakedTokens reflects amounts staked by users
        assertEq(
            pool.totalStakedTokens(),
            amountStakedUserA + amountStakedUserB
        );

        // rewardPerTokenStored updated correctly
        assertEq(pool.rewardPerTokenStored(), pool.rewardPerToken());

        // User earnings properly updated
        assertEq(userEarned(userA), pool.earned(userA));
        assertEq(userEarned(userB), pool.earned(userB));

        // stakeToken pool balance increases by total amounts staked
        assertEq(
            stakeToken.balanceOf(address(pool)) - poolBalanceBefore,
            amountStakedUserA + amountStakedUserB
        );

        // user stakeToken balances reduced by amount staked
        assertEq(
            amountStakedUserA - stakeToken.balanceOf(userA),
            amountStakedUserA
        );

        assertEq(
            amountStakedUserB - stakeToken.balanceOf(userB),
            amountStakedUserB
        );
    }

    function testStakeZeroAmount() public {
        uint256 REWARD_AMOUNT = 20e18;
        fundAndStartNewRewardPeriod(REWARD_AMOUNT);

        vm.startPrank(userA);
        // Cannot stake 0 tokens, expect revert
        vm.expectRevert(ERC20StakingPool.Error_ZeroAmount.selector);
        pool.stake(0);
        vm.stopPrank();
    }

    /// -----------------------------------------------------------------------
    /// Testing: `withdraw(uint256 amount)`
    /// -----------------------------------------------------------------------
    function testWithdraw() public {
        uint256 REWARD_AMOUNT = 20e18;
        fundAndStartNewRewardPeriod(REWARD_AMOUNT);

        // User A stakes entire balance
        vm.startPrank(userA);
        uint256 amountStakedUserA = stakeToken.balanceOf(userA);
        pool.stake(amountStakedUserA);
        vm.stopPrank();

        // userA staked entire stakeToken balance, so account balance should be 0
        assertEq(stakeToken.balanceOf(userA), 0);

        // Skip forward 4 days
        vm.warp(block.timestamp + 4 days);

        vm.startPrank(userA);
        pool.withdraw(amountStakedUserA);
        vm.stopPrank();

        // After withdraw, userA stakeToken balance should be amount staked
        assertEq(stakeToken.balanceOf(userA), amountStakedUserA);
    }

    function testWithdrawAmountExceedingBalance() public {
        uint256 REWARD_AMOUNT = 20e18;
        fundAndStartNewRewardPeriod(REWARD_AMOUNT);

        // User A stakes entire balance
        vm.startPrank(userA);
        uint256 amountStakedUserA = stakeToken.balanceOf(userA);
        pool.stake(amountStakedUserA);
        vm.stopPrank();

        // Skip forward 4 days
        vm.warp(block.timestamp + 4 days);

        vm.startPrank(userA);
        // Cannot withdraw an amount greater than the account balance, expect revert
        vm.expectRevert(
            ERC20StakingPool.Error_AmountExceedsStakerBalance.selector
        );
        pool.withdraw(amountStakedUserA + 10e18);
        vm.stopPrank();
    }

    /// -----------------------------------------------------------------------
    /// Testing: `getRewards()`
    /// -----------------------------------------------------------------------
    function testGetRewards() public {
        uint256 REWARD_AMOUNT = 20e18;
        fundAndStartNewRewardPeriod(REWARD_AMOUNT);

        assertEq(rewardToken.balanceOf(address(pool)), REWARD_AMOUNT);

        // User A stakes entire balance
        vm.startPrank(userA);
        uint256 amountStakedUserA = stakeToken.balanceOf(userA);
        pool.stake(amountStakedUserA);
        vm.stopPrank();

        // Skip forward 4 days
        vm.warp(block.timestamp + 4 days);

        uint256 rewardsToUserA = pool.earned(userA);

        vm.startPrank(userA);
        pool.getRewards();
        vm.stopPrank();

        // rewardToken pool balance reduced by rewardsToUserA
        assertEq(
            REWARD_AMOUNT - rewardsToUserA,
            rewardToken.balanceOf(address(pool))
        );

        // stakeToken balance of userA should be 0, since stake tokens not withdrawn
        assertEq(stakeToken.balanceOf(userA), 0);

        // stakeToken balance of pool should also be unchanged
        assertEq(stakeToken.balanceOf(address(pool)), amountStakedUserA);
    }

    function testGetRewardsZeroRewards() public {
        uint256 REWARD_AMOUNT = 20e18;
        fundAndStartNewRewardPeriod(REWARD_AMOUNT);

        uint256 rewardTokenBalanceUserABefore = rewardToken.balanceOf(userA);

        // User A stakes entire balance
        vm.startPrank(userA);
        uint256 amountStakedUserA = stakeToken.balanceOf(userA);
        pool.stake(amountStakedUserA);
        pool.getRewards();
        vm.stopPrank();

        // userA hasn't earnt any rewards
        assertEq(pool.earned(userA), 0);

        // No rewards transferred to userA
        assertEq(
            stdMath.delta(
                rewardTokenBalanceUserABefore,
                rewardToken.balanceOf(userA)
            ),
            0
        );
    }

    /// -----------------------------------------------------------------------
    /// Testing: `exitPoolWithStakeAndRewards()`
    /// -----------------------------------------------------------------------

    function testExitPoolWithStakeAndRewards() public {
        uint256 REWARD_AMOUNT = 20e18;
        fundAndStartNewRewardPeriod(REWARD_AMOUNT);

        uint256 userAInitialRewardTokenBalance = rewardToken.balanceOf(userA);

        uint256 poolInitialRewardTokenBalance = rewardToken.balanceOf(
            address(pool)
        );
        uint256 poolInitialStakeTokenBalance = stakeToken.balanceOf(
            address(pool)
        );

        // User A stakes entire balance
        vm.startPrank(userA);
        uint256 amountStakedUserA = stakeToken.balanceOf(userA);
        pool.stake(amountStakedUserA);
        vm.stopPrank();

        // Skip forward 8 days
        vm.warp(block.timestamp + 8 days);

        uint256 userARewardsEarned = userEarned(userA);
        uint256 poolStakedBalanceBeforeWithdrawal = stakeToken.balanceOf(
            address(pool)
        );

        // Exit pool with staked tokens and accumulated rewards
        vm.startPrank(userA);
        pool.exitPoolWithStakeAndRewards();
        vm.stopPrank();

        // userA rewardToken balance increases correctly
        assertEq(
            userAInitialRewardTokenBalance + pool.earned(userA),
            userEarned(userA)
        );

        // userA stake tokens balance: amountStakedUserA -> 0 -> amountStakedUserA, so change should be 0.
        assertEq(
            stdMath.delta(amountStakedUserA, stakeToken.balanceOf(userA)),
            0
        );

        // Following state variables for userA should now be set to 0.
        assertEq(pool.rewards(userA), 0);
        assertEq(pool.balanceOfStaker(userA), 0);

        // Reward token balance of user increased by rewards earned.
        assertEq(rewardToken.balanceOf(userA), userARewardsEarned);

        assertEq(
            poolInitialRewardTokenBalance - rewardToken.balanceOf(userA),
            rewardToken.balanceOf(address(pool))
        );

        assertEq(
            poolInitialStakeTokenBalance,
            poolStakedBalanceBeforeWithdrawal - amountStakedUserA
        );
    }

    /// -----------------------------------------------------------------------
    /// Helper functions
    /// -----------------------------------------------------------------------
    function fundAndStartNewRewardPeriod(uint256 REWARD_AMOUNT) public {
        vm.startPrank(poolOwner);

        rewardToken.transfer(address(pool), REWARD_AMOUNT);
        pool.newRewardPeriod(REWARD_AMOUNT);

        vm.stopPrank();
    }

    function userEarned(address user) public view returns (uint256) {
        return
            pool.rewards(user) +
            (pool.balanceOfStaker(user) *
                (pool.rewardPerToken() - pool.rewardPerTokenPaid(user))) /
            pool.precision();
    }
}
