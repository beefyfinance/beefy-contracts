// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/common/IUniswapRouterETH.sol";
import "../utils/GasThrottler.sol";

contract GasPrice is Ownable, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public bifi = address(0xCa3F508B8e4Dd382eE878A314789373D80A5190A);

    address public treasury;
    address public rewardPool;
    address public unirouter;

    // Fee constants
    uint constant public TREASURY_FEE = 140;
    uint constant public REWARD_POOL_FEE = 860;
    uint constant public MAX_FEE = 1000;

    address[] public wbnbToBifiRoute = [wbnb, bifi];

    constructor(address _treasury, address _rewardPool, address _unirouter) public {
        treasury = _treasury;
        rewardPool = _rewardPool;
        unirouter = _unirouter;
    }

    event NewRewardPool(address oldRewardPool, address newRewardPool);
    event NewTreasury(address oldTreasury, address newTreasury);
    event NewUnirouter(address oldUnirouter, address newUnirouter);

    modifier onlyEOA() {
        require(msg.sender == tx.origin, "!EOA");
        _;
    }

    // Main function. Divides Beefy's profits.
    function harvest() public onlyEOA gasThrottle {
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));

        uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
        IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now);
        
        uint256 rewardsFeeAmount = wbnbBal.mul(REWARD_POOL_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(rewardPool, rewardsFeeAmount);
    }

    // Manage the contract
    function setRewardPool(address _rewardPool) external onlyOwner {
        emit NewRewardPool(rewardPool, _rewardPool);
        rewardPool = _rewardPool;
    }

    function setTreasury(address _treasury) external onlyOwner {
        emit NewTreasury(treasury, _treasury);
        treasury = _treasury;
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        emit NewUnirouter(unirouter, _unirouter);
        unirouter = _unirouter;
    }
    
    // Rescue locked funds sent by mistake
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != wbnb, "!safe");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}