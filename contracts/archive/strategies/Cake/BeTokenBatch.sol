// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";


interface IRewardPool {
    function notifyRewardAmount(uint256 amount) external;
    function transferOwnership(address owner) external;
}

contract BeTokenBatch is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public want;
    IERC20 public native;
    IRewardPool public rewardPool;
    address public beefyFeeBatch;
    IUniswapRouterETH public unirouter; 
    address[] public route;

    uint256 public constant MAX = 10000;
    uint256 public fee = 1000; 

    event NewRewardPool(IRewardPool oldRewardPool, IRewardPool newRewardPool);
    event NewFeeBatch(address oldFeeBatch, address newFeeBatch);
    event NewUnirouter(IUniswapRouterETH oldUnirouter, IUniswapRouterETH newUnirouter);
    event NewRoute(address[] oldRoute, address[] newRoute);
    event UpdateFee(uint256 oldFee, uint256 newFee);
    event Harvested(uint256 fee, uint256 reward);

    constructor(
        address _rewardPool,
        address _unirouter, 
        address _beefyFeeBatch,
        address[] memory _route
    ) {
        rewardPool = IRewardPool(_rewardPool);
        unirouter = IUniswapRouterETH(_unirouter);
        beefyFeeBatch = _beefyFeeBatch;
        route = _route;

        want = IERC20(route[0]);
        native = IERC20(route[route.length -1]);

        want.safeApprove(address(unirouter), type(uint256).max);
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // Main function. Harvest and notify beCake reward pool.
    function harvest() public {
        require(balanceOfWant() > 0, "nothing to harvest");
        
        // Charge the fee
        uint256 feeBal;
        if (fee > 0) {
            feeBal = balanceOfWant() * fee / MAX;
            unirouter.swapExactTokensForTokens(feeBal, 0, route, beefyFeeBatch, block.timestamp);
        }

        uint256 wantBal = balanceOfWant();
        want.safeTransfer(address(rewardPool), wantBal);
        rewardPool.notifyRewardAmount(wantBal);
        emit Harvested(feeBal, wantBal);
    }

    // Manage the contract
    function setRewardPool(IRewardPool _rewardPool) external onlyOwner {
        emit NewRewardPool(rewardPool, _rewardPool);
        rewardPool = _rewardPool;
    }

    function setFeeBatch(address _feeBatch) external onlyOwner {
        emit NewFeeBatch(beefyFeeBatch, _feeBatch);
        beefyFeeBatch = _feeBatch;
    }
     
     
    function setUnirouter(IUniswapRouterETH _unirouter) external onlyOwner {
        emit NewUnirouter(unirouter, _unirouter);
        want.safeApprove(address(unirouter), 0);
        want.safeApprove(address(_unirouter), type(uint256).max);
        unirouter = _unirouter;
        
    }

     function setRoute(address[] memory _route) external onlyOwner {
        emit NewRoute(route, _route);
        require(_route[0] == address(want) && _route[_route.length - 1] == address(native), "!want || !native");
        route = _route;
    }

    function updateFee(uint256 _fee) external onlyOwner {
        emit UpdateFee(fee, _fee);
        require(fee <= 1000, "fee too large");
        fee = _fee;
    }
    
    // Rescue locked funds sent by mistake
    function inCaseTokensGetStuck(address _token, address _recipient) external onlyOwner {
        require(_token != address(want), "!safe");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_recipient, amount);
    }

    function transferRewardPoolOwnership(address _newOwner) public onlyOwner {
        IRewardPool(rewardPool).transferOwnership(_newOwner);
    }
}