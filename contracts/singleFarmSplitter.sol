// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";


interface ISinglePool {
    function addRewardToPool(uint256 reward) external; 
}

// Simple contract to split balances between different single token farms
// To be used by the proxies when triggering the buyback function
// The only purpose of this contract is to allow a global location for customizing
// Single staking pools inside the AvaOne ecosystem
contract singleFarmSplitter is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    
    struct SinglePool {
        ISinglePool targetPool;
        uint256 allocPoint;
    }

    // The AVAO token.
    IERC20 immutable public avaone;
    // List of the target pools
    SinglePool[] public poolInfo;
    // total allocation points
    uint256 totalAllocPoint;
    // Set of targetPools (this is used to prevent duplicates)
    EnumerableSet.AddressSet private poolList;

    event Add(uint256 indexed pid, uint256 allocPoint, ISinglePool indexed targetPool);
    event Set(uint256 indexed pid, uint256 allocPoint);
    event AddedToReward(uint256 indexed pid, uint256 amount);

    constructor (
        IERC20 _avaone
    ) {
        avaone = _avaone;
    }

    // Add a new target pool to the contract, can only be called by owner
    // Does **not** allow to add the same target pool twice, that would cause it to break severely.
    function add(
        uint256 _allocPoint,
        ISinglePool _targetPool
    ) external onlyOwner {
        require(!poolList.contains(address(_targetPool)), "add: targetPool already added");
        require(address(_targetPool) != address(0), "add: proxy is required");

        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            SinglePool({
                targetPool: _targetPool,
                allocPoint: _allocPoint
            })
        );
        poolList.add(address(_targetPool));
        emit Add(poolInfo.length.sub(1), _allocPoint, _targetPool);
    }

    // Update the target pool with the desired allocation.
    // Can only be called by owner
    function set(
        uint256 _pid,
        uint256 _allocPoint
    ) external onlyOwner {
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        emit Set(
            _pid,
            _allocPoint
        );
    }

    function addRewardToPool(uint256 reward) external nonReentrant {
        require(reward > 0, "Cannot add 0 to reward");
        avaone.safeTransferFrom(msg.sender, address(this), reward);
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            SinglePool storage pool = poolInfo[pid];

            if (pool.allocPoint > 0) {
                if (reward >= avaone.allowance(address(this), address(pool.targetPool)) ) {
                    avaone.approve(address(pool.targetPool), type(uint256).max);
                }
                uint256 rewardToPool = reward.mul(pool.allocPoint).div(totalAllocPoint);
                pool.targetPool.addRewardToPool(rewardToPool);
                
                emit AddedToReward(pid, rewardToPool);
            }
        }
    }  
}