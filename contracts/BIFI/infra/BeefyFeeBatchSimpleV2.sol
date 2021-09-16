// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface IRewardPool {
    function notifyRewardAmount(uint256 amount) external;
    function transferOwnership(address owner) external;
}

contract BeefyFeeBatchSimpleV2 is Ownable {
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
    ) public {
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
        IRewardPool(rewardPool).notifyRewardAmount(rewardPoolAmount);
    }
    
    // Rescue locked funds sent by mistake
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != wNative, "!safe");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }

    function transferRewardPoolOwnership(address _newOwner) external onlyOwner {
        IRewardPool(rewardPool).transferOwnership(_newOwner);
    }
}