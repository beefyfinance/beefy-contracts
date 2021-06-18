// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
pragma abicoder v1;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract BeefyFeeBatchSimple is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public immutable treasury;
    address public immutable rewardPool;
    address public immutable wNative ;

    // Fee constants
    uint constant public TREASURY_FEE = 140;
    uint constant public REWARD_POOL_FEE = 860;
    uint constant public MAX_FEE = 1000;

    constructor(
        address _treasury,
        address _rewardPool,
        address _wNative
    ) {
        treasury = _treasury;
        rewardPool = _rewardPool;
        wNative  = _wNative ;
    }

    // Main function. Divides Beefy's profits.
    function harvest() public {
        uint256 wNativeBal = IERC20(wNative).balanceOf(address(this));

        uint256 treasuryAmount = wNativeBal.mul(TREASURY_FEE).div(MAX_FEE);
        IERC20(wNative).safeTransfer(treasury, treasuryAmount);

        uint256 rewardPoolAmount = wNativeBal.mul(REWARD_POOL_FEE).div(MAX_FEE);
        IERC20(wNative).safeTransfer(rewardPool, rewardPoolAmount);
    }

    // Rescue locked funds sent by mistake
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != wNative, "!safe");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}