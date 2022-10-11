// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract ERC20StakingPool is Ownable {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error Error_ZeroAmount();
    error Error_InsufficientRewardTokensInPool();

    /// -----------------------------------------------------------------------
    /// Constant variables
    /// -----------------------------------------------------------------------
    uint256 internal constant precision = 1e30; // try to change this to 1e18.

    /// -----------------------------------------------------------------------
    /// Immutable variables
    /// -----------------------------------------------------------------------

    /// @notice The ERC-20 reward token for staking
    IERC20 public immutable rewardToken;

    /// @notice The ERC-20 token to be staked
    IERC20 public immutable stakeToken;

    /// @notice The reward period duration
    uint256 public immutable duration;

    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------

    /// @notice The last update time (Unix) when the rewards per token stored were updated
    uint256 public updateTime;

    /// @notice The end of the current reward period (Unix)
    uint256 public endCurrentRewardPeriod;

    /// @notice Reward rate per second
    uint256 public rewardRate;

    /// @notice Last updated reward per token
    uint256 public rewardPerTokenStored;

    /// @notice Total supply of staked tokens in the staking pool
    uint256 public totalStakedTokens;

    /// @notice Amount of tokens staked by a staker
    mapping(address => uint256) public balanceOfStaker;

    /// @notice Value of rewards per token when staker last staked/withdrew rewards
    mapping(address => uint256) public rewardPerTokenPaid;

    /// @notice Rewards earned when staker last staked/withdrew rewards
    mapping(address => uint256) public rewards;

    constructor(
        address _rewardToken,
        address _stakeToken,
        uint256 _duration
    ) {
        rewardToken = IERC20(_rewardToken);
        stakeToken = IERC20(_stakeToken);
        duration = _duration;
    }

    /// -----------------------------------------------------------------------
    /// User actions
    /// -----------------------------------------------------------------------

    function stake(uint256 amount) external {
        if (amount == 0) revert Error_ZeroAmount();

        /*=== Load state variables ===*/
        uint256 accountBalance = balanceOfStaker[msg.sender];

        uint256 lastRewardTime_ = lastRewardTime();
        uint256 totalStakedTokens_ = totalStakedTokens;
        uint256 rewardPerToken_ = _rewardPerToken(
            rewardRate,
            totalStakedTokens_,
            lastRewardTime_
        );

        /*=== Update state variables ===*/

        // rewards
        rewardPerTokenStored = rewardPerToken_;
        updateTime = lastRewardTime_;

        rewards[msg.sender] = _earned(
            msg.sender,
            accountBalance,
            rewardPerToken_,
            rewards[msg.sender]
        );

        rewardPerTokenPaid[msg.sender] = rewardPerToken_;

        // stake
        totalStakedTokens = totalStakedTokens_ + amount;
        balanceOfStaker[msg.sender] = accountBalance + amount;

        /*=== Effects ===*/
        stakeToken.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw() external {}

    function getRewards() external {}

    function exitPoolWithStakeAndRewards() external {}

    /// -----------------------------------------------------------------------
    /// Owner actions
    /// -----------------------------------------------------------------------

    /// @notice Starts a new reward period. Details:
    /// The reward tokens need to have been already transferred to this contract.
    /// Leftover rewards from previous reward period rolled over to new period.
    /// @param rewardAmount Amount of reward tokens in new reward period.
    function newRewardPeriod(uint256 rewardAmount) external onlyOwner {
        /*=== Checks ===*/
        if (rewardAmount == 0) revert Error_ZeroAmount();

        /*=== Load state variables ===*/
        uint256 endCurrentRewardPeriod_ = endCurrentRewardPeriod;
        uint256 lastUpdateTime_ = block.timestamp < endCurrentRewardPeriod_
            ? block.timestamp
            : endCurrentRewardPeriod_;
        uint256 rewardRate_ = rewardRate;
        uint256 totalStakedTokens_ = totalStakedTokens;

        /*=== Update state variables ===*/

        rewardPerTokenStored = _rewardPerToken(
            rewardRate_,
            totalStakedTokens_,
            lastUpdateTime_
        );

        updateTime = lastUpdateTime_;

        uint256 tempRewardRate;

        if (block.timestamp >= endCurrentRewardPeriod) {
            tempRewardRate = rewardAmount / duration;
        } else {
            uint256 remainingTime = (endCurrentRewardPeriod - block.timestamp);
            uint256 remainingRewards = remainingTime * rewardRate_;
            tempRewardRate = (rewardAmount * remainingRewards) / duration;
        }

        rewardRate = tempRewardRate;

        if (rewardToken.balanceOf(address(this)) < rewardRate * duration)
            revert Error_InsufficientRewardTokensInPool();

        updateTime = block.timestamp;
        endCurrentRewardPeriod = duration + block.timestamp;
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _rewardPerToken(
        uint256 _rewardRate,
        uint256 _totalStakedTokens,
        uint256 _lastRewardTime
    ) internal view returns (uint256) {
        if (_totalStakedTokens == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            ((precision * _rewardRate * (_lastRewardTime - updateTime)) /
                _totalStakedTokens);
    }

    function _earned(
        address account,
        uint256 accountBalance,
        uint256 rewardPerToken_,
        uint256 accountRewards
    ) internal view returns (uint256) {
        return
            accountRewards +
            (accountBalance * (rewardPerToken_ - rewardPerTokenPaid[account])) /
            precision;
    }

    /// -----------------------------------------------------------------------
    /// Getter functions
    /// -----------------------------------------------------------------------

    function lastRewardTime() public view returns (uint256) {
        return
            block.timestamp < endCurrentRewardPeriod
                ? block.timestamp
                : endCurrentRewardPeriod;
    }

    function rewardPerToken() external view returns (uint256) {
        return _rewardPerToken(rewardRate, totalStakedTokens, lastRewardTime());
    }

    function earned(address account) external view returns (uint256) {
        return
            _earned(
                account,
                balanceOfStaker[account],
                _rewardPerToken(
                    rewardRate,
                    totalStakedTokens,
                    lastRewardTime()
                ),
                rewards[account]
            );
    }
}
