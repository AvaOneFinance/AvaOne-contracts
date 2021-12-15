// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


/*interface IDepositProxy {
    using SafeERC20 for IERC20;

    function pendingRewards() external view returns (uint256);
    function deposit() external;
    function withdraw(uint256 amount) external;
    function getReward() external returns (uint256);
    function rewardToken() external view returns (address);
}*/

interface IRewarder {
    function onJoeReward(address user, uint256 newLpAmount) external;

    function pendingTokens(address user)
        external
        view
        returns (uint256 pending);

    function rewardToken() external view returns (address);
}

// We only need to call swapExactTokensForTokens, keep it minimal.
interface IUniswapRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

// We only need burn(), balanceOf(), approve(), allowance() and transfer(), keep it minimal

interface AvaOne {
    function burn(uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface SingleAvaoPool {
    function addRewardToPool(uint256 amount) external; 
}

interface traderJoePool {
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. JOEs to distribute per second.
        uint256 lastRewardTimestamp; // Last timestamp that JOEs distribution occurs.
        uint256 accJoePerShare; // Accumulated JOEs per share, times 1e12. See below.
        IRewarder rewarder;
    }
    
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }
    
    function userInfo(uint256 _pid, address _user) external view returns (traderJoePool.UserInfo memory);
    function poolInfo(uint256 _pid) external view returns (traderJoePool.PoolInfo memory);
    function devPercent() external view returns (uint256);
    function treasuryPercent() external view returns (uint256);
    function investorPercent() external view returns (uint256);
    function totalAllocPoint() external view returns (uint256);
    function joePerSec() external view returns (uint256);
    function deposit(uint256 _pid, uint256 _amount) external;
    function withdraw(uint256 _pid, uint256 _amount) external;
    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingJoe,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        );
    function emergencyWithdraw(uint256 _pid) external;
}

contract TraderJoeProxy is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    
    IERC20 public depositToken;
    IERC20 public rewardToken;
    IERC20 public controller;
    AvaOne public avaone;
    uint256 public buybackPercentage;
    uint256 public burnPercentage;
    uint256 public targetPoolId;
    traderJoePool targetPool;
    SingleAvaoPool singleAvaoPool;
    IUniswapRouter public uniswapRouter;
    address[] public uniswapRouting;
    bool emergencied;
    
    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event Approve(uint256 amount);
    event Buyback(uint256 amount);
    event BuybackAndBurn(uint256 buyback, uint256 burn);
    event Emergency(uint256 amount);
    
    constructor(
        IERC20 _depositToken,
        IERC20 _rewardToken,
        IERC20 _controller,
        AvaOne _avaone,
        traderJoePool _targetPool,
        SingleAvaoPool _singleAvaoPool,
        uint256 _targetPoolId,
        IUniswapRouter _uniswapRouter, 
        address[] memory _uniswapRouting,
        uint256 _buybackPercentage,
        uint256 _burnPercentage
    ) {
        require(buybackPercentage < 1000,"Buyback Percentage cannot be 100%");
        depositToken = _depositToken;
        rewardToken = _rewardToken;
        controller = _controller;
        targetPool = _targetPool;
        targetPoolId = _targetPoolId;
        uniswapRouter = _uniswapRouter;
        uniswapRouting = _uniswapRouting;
        buybackPercentage = _buybackPercentage;
        burnPercentage = _burnPercentage;
        singleAvaoPool = _singleAvaoPool;
        avaone = _avaone;
    }
    
    modifier controllerOnly() {
        require(msg.sender == address(controller), "Account doesn't have controller privillege");
        _;
    }
    
    function pendingRewards() external view returns (uint256) {
        (uint256 pendingReward,,,) = targetPool.pendingTokens(targetPoolId, address(this));
        return pendingReward;
    }
    
    // Before calling deposit, the controller sends us a transaction
    // Containing the deposit token.
    // So we need to deposit all this contract depositToken balance to the target pool.
    function deposit() external controllerOnly returns (uint256) {
        require (!emergencied, "Emergency was enabled, withdraw your tokens instead");
        uint256 balance = depositToken.balanceOf(address(this));
        uint256 approval = depositToken.allowance(address(this), address(targetPool));
        if (balance >= approval) {
            depositToken.approve(address(targetPool), 2**256 -1);
            emit Approve(2**256-1);
        }
        targetPool.deposit(targetPoolId, balance);
        emit Deposit(balance);
        return balance;
    }
    
    // Withdraw from target pool and send back to the controller.
    // The controller handles the user balance, and it will send to him accordingly
    function withdraw(uint256 _amount) external controllerOnly returns (uint256) {
        require (!emergencied, "Emergency was enabled, withdraw your tokens instead");
        targetPool.withdraw(targetPoolId, _amount);
        depositToken.safeTransfer(address(controller), _amount);
        emit Withdraw(_amount);
        return _amount;
    }
    
    // Simple function to send the rewards from the targetPool back to the controller.
    // It keeps a balance in this contract that will be used when calling
    // buyback() in the future
    function getReward() external controllerOnly returns (uint256) {
        uint256 previousBalance = rewardToken.balanceOf(address(this));
        targetPool.withdraw(targetPoolId, 0);
        uint256 balanceDifference = rewardToken.balanceOf(address(this)).sub(previousBalance);
        uint256 buybackBalance = balanceDifference.mul(buybackPercentage).div(1000);
        uint256 poolReward = balanceDifference.sub(buybackBalance);
        // Transfer all to the controller contract
        rewardToken.safeTransfer(address(controller), poolReward);
        return poolReward;
    }
    
    // Simple helper function to calculate APY on frontend.
    function get24HRewardForPool() external view returns (uint256) {
        uint256 poolAllocPoint = targetPool.poolInfo(targetPoolId).allocPoint;
        uint256 totalAllocPoint = targetPool.totalAllocPoint();
        uint256 poolLpAmount = depositToken.balanceOf(address(targetPool));
        uint256 proxyLpAmount =  targetPool.userInfo(targetPoolId, address(this)).amount;
        uint256 joePerSec = targetPool.joePerSec();
        
        uint256 rewardFor24H = joePerSec.mul(86400).mul(poolAllocPoint).div(totalAllocPoint).mul(proxyLpAmount).div(poolLpAmount);
        return rewardFor24H;
    }

    // Change the percentages for how much is kept on the Contract
    // And how much is burning when buyback() is called
    function setBuybackAndBurn(uint256 _buyback, uint256 _burn) public onlyOwner {
        require (_buyback < 1000, "Cannot set higher than 100%");
        require (_burn < 1000, "Cannot set higher than 100%");
        buybackPercentage = _buyback;
        burnPercentage = _burn;

        emit BuybackAndBurn(_buyback, _burn);
    }

    // Buyback:
    // Sell all remaining rewardTokens from the target pool for AVAO'safe
    // Then burn the _burn percetange of the AVAO tokens
    // And send the remaining balance to the single staking AVAO pool.
    function buyback() public {
        require(rewardToken.balanceOf(address(this)) > 0, "Cannot buyback 0");
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        if (rewardTokenBalance >= rewardToken.allowance(address(this), address(uniswapRouter))) {
            rewardToken.approve(address(uniswapRouter), 2**256 -1);
        }
        uniswapRouter.swapExactTokensForTokens(
            rewardTokenBalance,
            0, // We don't care for price impact
            uniswapRouting,
            address(this),
            block.timestamp
            );
        // After buyback, burn the correct percentage, then move to the staking pool the remaining
        uint256 balance = avaone.balanceOf(address(this));
        uint256 burnValue = balance.mul(burnPercentage).div(1000);
        avaone.burn(burnValue);
        // Pay the user 1% of the rewards for paying for the transaction fees
        uint256 userReward = avaone.balanceOf(address(this)).div(100);
        avaone.transfer(address(msg.sender), userReward);
        // Send remaining to the single staking contract.
        if (balance > avaone.allowance(address(this), address(singleAvaoPool))) {
            avaone.approve(address(singleAvaoPool), 2**256-1);
        }
        singleAvaoPool.addRewardToPool(avaone.balanceOf(address(this)));
        emit Buyback(balance); 
    }

    // Once emergency withdraw is enabled, It will remove all the LP tokens
    // from the target contract, and allow users from the MasterAvao contract
    // To call emergencyWithdraw
    // This should be only necessary if something bad happens with the target pool.
    // All the tokens will be moved from the target pool, to the proxy and them to the master Contract.
    // Which then users will be able to recover their balances by calling emergencyWithdraw directly.
    // If a user wants to emergencyWithdraw from the master contract
    // and !emergencied, it will simply withdraw for that user.
    function enableEmergency() public onlyOwner {
        emergencied = true;
        targetPool.emergencyWithdraw(targetPoolId);
        uint256 balance = depositToken.balanceOf(address(this));
        depositToken.safeTransfer(address(controller), balance);
        emit Emergency(balance);
    }
}
