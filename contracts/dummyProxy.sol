// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


/* interface IDepositProxy {
    function pendingRewards() external view returns (uint256);
    function deposit() external;
    function withdraw(uint256 amount) external;
    function getReward() external returns (uint256);
    function rewardToken() external view returns (address);
    function emergencied() external view returns (bool);
    function get24HRewardForPool() external view returns (uint256); 
} */

contract dummyProxy is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable depositToken;
    IERC20 public immutable rewardToken;
    IERC20 public immutable controller;
    bool public emergencied;
    bool public paused;

    event Deposit();
    event Withdraw(uint256 _amount);
    event Emergency(uint256 amount);
    event Paused(bool status);
    
    constructor(
        IERC20 _depositToken,
        IERC20 _rewardToken,
        IERC20 _controller
    ) {
        depositToken = _depositToken;
        rewardToken = _rewardToken;
        controller = _controller;   
    }

    modifier controllerOnly() {
        require(msg.sender == address(controller), "Account doesn't have controller privillege");
        _;
    }

    // As this proxy is a dummy proxy (only store tokens), it does *not* create any reward.
    // Declared as view to keep it the same as other proxies and the controller.
    function pendingReward() external view returns (uint256) {
        return 0;
    }

    // Dummy function to allow MasterAvao to call it and not revert.
    function deposit() external controllerOnly {
        require (!paused, "Proxy is paused, cannot deposit");
        require (!emergencied, "Emergency was enabled, withdraw your tokens instead");
        emit Deposit();
    }

    // Withdraw from target pool and send back to the controller.
    // The controller handles the user balance, and it will send to him accordingly
    function withdraw(uint256 _amount) external controllerOnly {
        depositToken.safeTransfer(address(controller), _amount);
        emit Withdraw(_amount);
    }

    // Again, as this proxy is a dummmy proxy, it does not generate any reward, returns 0 to the controller.
    // Function declaration is kept the same so it does not revert when the controller calls it.
    function getReward() external controllerOnly returns (uint256) {
        require (!paused, "Proxy is paused, cannot getReward");
        return 0;
    }

    // As this proxy is a dummy proxy (only store tokens), it does *not* create any reward, returns 0 to controller.
    // Declared as view to keep it the same as other proxies and the controller.
    function get24HRewardForPool() external view returns (uint256) {
        return 0;
    }

    function enableEmergency() public onlyOwner {
        paused = true;
        emergencied = true;
        uint256 balance = depositToken.balanceOf(address(this));
        emit Emergency(balance);
        emit Paused(paused);
    }

    function setPause(bool _paused) external onlyOwner {
        require (!emergencied, "Cannot change pause status after emergency was enabled");
        paused = _paused;
        emit Paused(paused);
    }
}