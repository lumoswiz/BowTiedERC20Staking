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

        assertEq(pool.updateTime(), block.timestamp);
        assertEq(
            pool.endCurrentRewardPeriod(),
            block.timestamp + pool.duration()
        );
        assertEq(pool.rewardPerTokenStored(), 0);
        assertEq(pool.rewardRate(), REWARD_AMOUNT / pool.duration());
    }

    function testNewRewardPeriodWithNoRewardTokensInPool() public {
        uint256 REWARD_AMOUNT = 20e18;

        vm.prank(poolOwner);
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

        // User A stakes entire balance
        vm.startPrank(userA);
        uint256 amountStakedUserA = stakeToken.balanceOf(userA);
        pool.stake(amountStakedUserA);
        vm.stopPrank();

        assertEq(pool.rewardPerTokenStored(), pool.rewardPerToken());

        // Skip forward 4 days
        vm.warp(block.timestamp + 4 days);

        // User B stakes entire balance
        vm.startPrank(userB);
        uint256 amountStakedUserB = stakeToken.balanceOf(userB);
        pool.stake(amountStakedUserB);
        vm.stopPrank();

        assertEq(pool.balanceOfStaker(userA), amountStakedUserA);
        assertEq(pool.balanceOfStaker(userB), amountStakedUserB);

        assertEq(
            pool.totalStakedTokens(),
            amountStakedUserA + amountStakedUserB
        );

        assertEq(pool.rewardPerTokenStored(), pool.rewardPerToken());

        assertEq(pool.rewards(userA), pool.earned(userA));
        emit log_uint(pool.earned(userA));
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
}
