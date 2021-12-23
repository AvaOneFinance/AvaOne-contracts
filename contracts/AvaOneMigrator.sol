// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract AvaOneMigrator is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable oldAvaOne;
    IERC20 public immutable newAvaOne;

    event Migrated(uint256 amount);

    constructor (
        IERC20 _oldAvaOne,
        IERC20 _newAvaOne
    ) {
        oldAvaOne = _oldAvaOne;
        newAvaOne = _newAvaOne;
    }

    function migrate(uint256 amount) external nonReentrant {
        require (oldAvaOne.balanceOf(msg.sender) >= amount, "migrate: cannot migrate more than your balance");
        oldAvaOne.transferFrom(msg.sender, address(this), amount);
        newAvaOne.transfer(msg.sender, amount);
        emit Migrated (amount);
    }
}