pragma solidity ^0.5.16;


// Use this when deploying with REMIX
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v2.4.0/contracts/math/Math.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v2.4.0/contracts/math/SafeMath.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v2.4.0/contracts/ownership/Ownable.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v2.4.0/contracts/token/ERC20/ERC20Detailed.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v2.4.0/contracts/token/ERC20/SafeERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v2.4.0/contracts/utils/ReentrancyGuard.sol";

import "./OpenZeppelin/v2.4.0/contracts/math/Math.sol";
import "./OpenZeppelin/v2.4.0/contracts/math/SafeMath.sol";
import "./OpenZeppelin/v2.4.0/contracts/ownership/Ownable.sol";
import "./OpenZeppelin/v2.4.0/contracts/token/ERC20/ERC20Detailed.sol";
import "./OpenZeppelin/v2.4.0/contracts/token/ERC20/SafeERC20.sol";
import "./OpenZeppelin/v2.4.0/contracts/utils/ReentrancyGuard.sol";

// Inheritance
import "./interfaces/IStakingRewards.sol";
import "./Pausable.sol";

// https://docs.synthetix.io/contracts/source/contracts/stakingrewards
contract StakingPool is IStakingRewards, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public avao; // AVAO
    uint256 public periodFinish = 0;  // Timestamp limit for staking rewards
    uint256 public rewardRate = 0;  // How many tokens will be distributed during rewards duration
    uint256 public rewardsDuration = 7 days;  // Time interval during which rewards will be distributed
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    mapping(address => bool) public whitelisted;

    uint256 private _totalSupply; // Total LP currently in pool
    mapping(address => uint256) private _balances;  // LP balances for each user

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _owner,
        IERC20 _avao
    ) public Owned(_owner) {
        avao = _avao;
    }

    /* ========== VIEWS ========== */
    function totalSupply() external view returns (uint256) { return _totalSupply; }
    function balanceOf(address account) external view returns (uint256) { return _balances[account]; }
    function lastTimeRewardApplicable() public view returns (uint256) { return Math.min(block.timestamp, periodFinish); }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) { return rewardPerTokenStored; }
        return rewardPerTokenStored.add(
            lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
        );
    }

    function earned(address account) public view returns (uint256) {
        return _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(rewards[account]);
    }

    function getRewardForDuration() external view returns (uint256) { return rewardRate.mul(rewardsDuration); }

    function get24HRewardForPool() external view returns (uint256) {
        uint256 accumulativeRewards = rewardRate.mul(86400);
        return accumulativeRewards;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant notPaused updateReward(msg.sender) {
        require (msg.sender == tx.origin || whitelisted[msg.sender],
                "Sender is a contract and it is not allowed to interact with this contract");
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        avao.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require (msg.sender == tx.origin || whitelisted[msg.sender],
                "Sender is a contract and it is not allowed to interact with this contract");
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        avao.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            avao.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }


    function addRewardToPool(uint256 reward) external updateReward(address(0)) {
        require(reward > 0, "Cannot add 0 to reward");
        avao.safeTransferFrom(msg.sender, address(this), reward);
        uint256 newReward = 0;
        if (block.timestamp > periodFinish) {
            newReward = reward;
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            newReward = leftover.add(reward);
        }
        rewardRate = newReward.div(rewardsDuration).sub(1);
        require(rewardRate <= newReward.div(rewardsDuration), "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyOwner {
        require(tokenAddress != address(avao), "Cannot withdraw the staking token");
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    // Add a contract address to whitelist
    function addToWhitelist(address _address) external onlyOwner {
        whitelisted[_address] = true;
        emit AddToWhitelist(_address);
    }

    // Remove a contract address from whitelist
    function removeFromWhitelist(address _address) external onlyOwner {
        whitelisted[_address] = false;
        emit RemoveFromWhitelist(_address);
    }


    /* ========== MODIFIERS ========== */

    // Update the reward for a given Account
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    event AddToWhitelist(address _address);
    event RemoveFromWhitelist(address _address);
}

