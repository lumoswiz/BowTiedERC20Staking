// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";

contract ERC20StakingPool is Ownable {
    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error Error_ZeroRewardAmount();
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

    function stake() external {}

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
        if (rewardAmount == 0) revert Error_ZeroRewardAmount();

        /*=== Load state variables ===*/
        uint256 _endCurrentRewardPeriod = endCurrentRewardPeriod;
        uint256 _lastUpdateTime = block.timestamp < _endCurrentRewardPeriod
            ? block.timestamp
            : _endCurrentRewardPeriod;
        uint256 _rewardRate = rewardRate;
        uint256 _duration = duration;
        uint256 _totalStakedTokens = totalStakedTokens;

        /*=== Update state variables ===*/

        rewardPerTokenStored = _rewardPerToken(
            _rewardRate,
            _totalStakedTokens,
            _lastUpdateTime
        );

        updateTime = _lastUpdateTime;

        uint256 tempRewardRate;

        if (block.timestamp >= endCurrentRewardPeriod) {
            tempRewardRate = rewardAmount / _duration;
        } else {
            uint256 remainingTime = (endCurrentRewardPeriod - block.timestamp);
            uint256 remainingRewards = remainingTime * _rewardRate;
            tempRewardRate = (rewardAmount * remainingRewards) / _duration;
        }

        rewardRate = tempRewardRate;

        if (rewardToken.balanceOf(address(this)) < rewardRate * duration)
            revert Error_InsufficientRewardTokensInPool();

        updateTime = block.timestamp;
        endCurrentRewardPeriod = _duration + block.timestamp;
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

    function _earned() internal view returns (uint256) {}

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

    function earned() external view returns (uint256) {}
}
