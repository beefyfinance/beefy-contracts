// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract BeefyRefund {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address constant public dead = address(0x000000000000000000000000000000000000dEaD);
    address public token;
    address public mootoken;
    
    uint256 public pricePerFullShare;

    constructor(address _token, address _mootoken, uint256 _pricePerFullShare) public {
        token = _token;
        mootoken = _mootoken;
        pricePerFullShare = _pricePerFullShare;
    }

    function refund() external {
        require(!Address.isContract(msg.sender), "!contract");

        uint256 balance = IERC20(mootoken).balanceOf(msg.sender);
        IERC20(mootoken).safeTransferFrom(msg.sender, dead, balance);

        uint256 refundAmount = balance.mul(pricePerFullShare).div(1e18);
        IERC20(token).safeTransfer(msg.sender, refundAmount);
    }
}
