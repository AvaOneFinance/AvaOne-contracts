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

interface lydiaPool {
    struct PoolInfo {
        IERC20 lpToken;               // Address of LP token contract.
        uint256 allocPoint;           // How many allocation points assigned to this pool. LYDs to distribute per second.
        uint256 lastRewardTimestamp;  // Last timestamp that LYDs distribution occurs.
        uint256 accLydPerShare;       // Accumulated LYDs per share, times 1e12. See below.
    }
    
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }
    
    function userInfo(uint256 _pid, address _user) external view returns (lydiaPool.UserInfo memory);
    function poolInfo(uint256 _pid) external view returns (lydiaPool.PoolInfo memory);
    function lyd() external view returns (address);
    function devaddr() external view returns (address);
    function totalAllocPoint() external view returns (uint256);
    function lydPerSec() external view returns (uint256);
    function enterStaking(uint256 _amount) external;
    function leaveStaking(uint256 _amount) external;
    function pendingLyd(uint256 _pid, address _user) external view returns (uint256);
    function emergencyWithdraw(uint256 _pid) external;
}

contract lydiaSingleProxy is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    
    IERC20 public immutable lyd;
    IERC20 public immutable controller;
    AvaOne public immutable avaone;
    // This is mainly the only difference between the other proxies.
    // We keep the buyback balance on a variable instead of the balance of the contract itself.
    // because depositToken == rewardToken
    uint256 public buybackBalance;
    uint256 public buybackPercentage;
    uint256 public burnPercentage;
    uint256 public immutable targetPoolId;
    lydiaPool public immutable targetPool;
    SingleAvaoPool public immutable singleAvaoPool;
    IUniswapRouter public immutable uniswapRouter;
    address[] public uniswapRouting;
    bool public emergencied;
    
    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event Approve(uint256 amount);
    event Buyback(uint256 amount);
    event BuybackAndBurn(uint256 buyback, uint256 burn);
    event Emergency(uint256 amount);
    
    constructor(
        IERC20 _lyd,
        IERC20 _controller,
        AvaOne _avaone,
        lydiaPool _targetPool,
        SingleAvaoPool _singleAvaoPool,
        uint256 _targetPoolId,
        IUniswapRouter _uniswapRouter, 
        address[] memory _uniswapRouting,
        uint256 _buybackPercentage,
        uint256 _burnPercentage
    ) {
        require(_buybackPercentage < 1000,"constructor: Buyback Percentage cannot be 100%");
        require(_targetPool.lyd() == address(_lyd), "constructor: reward token doesn't match target pool");
        require(address(_targetPool.poolInfo(_targetPoolId).lpToken) == address(_lyd), "constructor: deposit token doesn't match target pool");
        lyd = _lyd;
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
        uint256 pendingReward = targetPool.pendingLyd(targetPoolId, address(this));
        return pendingReward;
    }
    
    // Before calling deposit, the controller sends us a transaction
    // Containing the deposit token.
    // So we need to deposit all this contract lyd balance minus the amount reserves to buyback to the target pool.
    function deposit() external controllerOnly nonReentrant {
        require (!emergencied, "Emergency was enabled, withdraw your tokens instead");
        uint256 balance = lyd.balanceOf(address(this)).sub(buybackBalance);
        uint256 approval = lyd.allowance(address(this), address(targetPool));
        if (balance >= approval) {
            lyd.approve(address(targetPool), type(uint256).max);
            emit Approve(type(uint256).max);
        }
        targetPool.enterStaking(balance);
        emit Deposit(balance);
    }
    
    // Withdraw from target pool and send back to the controller.
    // The controller handles the user balance, and it will send to him accordingly
    function withdraw(uint256 _amount) external controllerOnly nonReentrant {
        if (!emergencied) {
            targetPool.leaveStaking(_amount);
        } // If the pool was emergencied, all the LP balance is locked inside this proxy contract
          // So, simply transfer it to the controller, which will transfer to the user.
        lyd.safeTransfer(address(controller), _amount);
        emit Withdraw(_amount);
    }
    
    // Simple function to send the rewards from the targetPool back to the controller.
    // It keeps a balance in this contract that will be used when calling
    // buyback() in the future
    function getReward() external controllerOnly nonReentrant returns (uint256) {
        uint256 previousBalance = lyd.balanceOf(address(this));
        targetPool.leaveStaking(0);
        uint256 balanceDifference = lyd.balanceOf(address(this)).sub(previousBalance);
        uint256 buybackDifference = balanceDifference.mul(buybackPercentage).div(1000);
        buybackBalance = buybackBalance.add(buybackDifference);
        uint256 poolReward = balanceDifference.sub(buybackDifference);
        // Transfer all to the controller contract
        lyd.safeTransfer(address(controller), poolReward);
        return poolReward;
    }
    
    // Simple helper function to calculate APY on frontend.
    function get24HRewardForPool() external view returns (uint256) {
        uint256 poolAllocPoint = targetPool.poolInfo(targetPoolId).allocPoint;
        uint256 totalAllocPoint = targetPool.totalAllocPoint();
        uint256 poolLpAmount = lyd.balanceOf(address(targetPool));
        if (poolLpAmount == 0 || totalAllocPoint == 0) { return 0; }
        uint256 proxyLpAmount =  targetPool.userInfo(targetPoolId, address(this)).amount;
        uint256 lydPerSec = targetPool.lydPerSec();
        
        uint256 rewardFor24H = lydPerSec.mul(86400).mul(poolAllocPoint).div(totalAllocPoint).mul(proxyLpAmount).div(poolLpAmount);
        return rewardFor24H;
    }

    // Change the percentages for how much is kept on the Contract
    // And how much is burning when buyback() is called
    function setBuybackAndBurn(uint256 _buyback, uint256 _burn) external onlyOwner {
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
    function buyback() external nonReentrant {
        require(buybackBalance > 0, "Cannot buyback 0");
        uint256 rewardTokenBalance = buybackBalance;
        if (rewardTokenBalance >= lyd.allowance(address(this), address(uniswapRouter))) {
            lyd.approve(address(uniswapRouter), type(uint256).max);
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
        if (balance >= avaone.allowance(address(this), address(singleAvaoPool))) {
            avaone.approve(address(singleAvaoPool), type(uint256).max);
        }
        singleAvaoPool.addRewardToPool(avaone.balanceOf(address(this)));
        // Reset buyback balance.
        buybackBalance = 0;
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
    function enableEmergency() external onlyOwner {
        emergencied = true;
        targetPool.emergencyWithdraw(targetPoolId);
        uint256 balance = lyd.balanceOf(address(this));
        emit Emergency(balance);
    }

    // View only functions to match Interface over MasterAvao
    function depositToken() external view returns (address) {
        return address(lyd);
    }

    function rewardToken() external view returns (address) {
        return address(lyd);
    }

}
