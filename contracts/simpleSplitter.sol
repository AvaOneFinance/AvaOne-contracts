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
    address public immutable okinaPrime;
    address public immutable satoku;
    address public immutable hashercat;
    address public immutable saito;
    address public immutable treasury;

    event SplitBalanceBetweenAddress(
        address _okinaPrime,
        uint256 _okinaPrimeSplit,
        address _satoku,
        uint256 _satokuSplit,
        address _hashercat,
        uint256 _hashercatSplit,
        address _treasury,
        uint256 _treasurySplit,
        address _saito,
        uint256 _saitoSplit
    );

   constructor(
        IERC20 _avaone,
        address _okinaPrime,
        address _satoku,
        address _hashercat,
        address _saito,
        address _treasury
    ) {
        avaone = _avaone;
        okinaPrime = _okinaPrime;
        satoku = _satoku;
        hashercat = _hashercat;
        saito = _saito;
        treasury = _treasury;
    }

    function splitBalanceBetweenAddress() external {
        require(avaone.balanceOf(address(this)) != 0, "Cannot split a balance of zero!");
        uint256 thirtyPercent = avaone.balanceOf(address(this)).mul(300).div(1000);
        uint256 sixPercent = avaone.balanceOf(address(this)).mul(60).div(1000);

        // 30% for okina
        avaone.safeTransfer(okinaPrime, thirtyPercent);
        // 30% for satoku
        avaone.safeTransfer(satoku, thirtyPercent);
        // 30% for hashercat
        avaone.safeTransfer(hashercat, thirtyPercent);
        // 6% for treasury.
        avaone.safeTransfer(treasury, sixPercent);
        // Remaining (4%) for saito
        uint256 saitoSplit = avaone.balanceOf(address(this));
        avaone.safeTransfer(saito, saitoSplit);
        emit SplitBalanceBetweenAddress(
            okinaPrime,
            thirtyPercent,
            satoku,
            thirtyPercent,
            hashercat,
            thirtyPercent,
            treasury,
            sixPercent,
            saito,
            saitoSplit
        );
    }
}