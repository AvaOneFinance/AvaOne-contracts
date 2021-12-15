// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract SimpleSplitter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 avaone; // The AvaOne token
    address public okinaPrime;
    address public satoku;
    address public hashercat;
    address public saito;

   constructor(
        IERC20 _avaone,
        address _okinaPrime,
        address _satoku,
        address _hashercat,
        address _saito
    ) {
        avaone = _avaone;
        okinaPrime = _okinaPrime;
        satoku = _satoku;
        hashercat = _hashercat;
        saito = _saito;
    }

    function splitBalanceBetweenAddress() public {
        require(avaone.balanceOf(address(this)) != 0, "Cannot split a balance of zero!");
        uint256 thirtyPercent = avaone.balanceOf(address(this)).mul(300).div(1000);

        // 30% for okina
        avaone.safeTransfer(okinaPrime, thirtyPercent);
        // 30% for satoku
        avaone.safeTransfer(satoku, thirtyPercent);
        // 30% for hashercat
        avaone.safeTransfer(hashercat, thirtyPercent);
        // Remaining (10%) for saito
        avaone.safeTransfer(saito, avaone.balanceOf(address(this)));
    }
}