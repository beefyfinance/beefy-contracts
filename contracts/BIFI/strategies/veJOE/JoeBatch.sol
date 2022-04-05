// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";


interface IRewardPool {
    function notifyRewardAmount(uint256 amount) external;
    function transferOwnership(address owner) external;
}

contract JoeBatch is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public joe;
    address public rewardPool;

    event NewRewardPool(address oldRewardPool, address newRewardPool);

    constructor(
        address _joe,
        address _rewardPool
    ) {
        joe = IERC20(_joe);
        rewardPool = _rewardPool;
    }

    // Main function. Harvest and notify beJOE reward pool.
    function harvest() public {
        uint256 joeBal = joe.balanceOf(address(this));

        joe.safeTransfer(rewardPool, joeBal);
        IRewardPool(rewardPool).notifyRewardAmount(joeBal);
    }

    // Manage the contract
    function setRewardPool(address _rewardPool) external onlyOwner {
        emit NewRewardPool(rewardPool, _rewardPool);
        rewardPool = _rewardPool;
    }
    
    // Rescue locked funds sent by mistake
    function inCaseTokensGetStuck(address _token, address _recipient) external onlyOwner {
        require(_token != address(joe), "!safe");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_recipient, amount);
    }

    function transferRewardPoolOwnership(address _newOwner) external onlyOwner {
        IRewardPool(rewardPool).transferOwnership(_newOwner);
    }
}