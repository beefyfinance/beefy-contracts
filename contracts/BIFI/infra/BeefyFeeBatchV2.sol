// SPDX-License-Identifier: MIT

pragma solidity 0.8.2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IRewardPool {
    function notifyRewardAmount(uint256 amount) external;
    function transferOwnership(address owner) external;
}

interface IUniswapRouter {
    function swapExactTokensForTokens(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline
    ) external returns (uint[] memory amounts);
}

contract BeefyFeeBatchV2 is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public wNative;
    IERC20Upgradeable public bifi;
    address public treasury;
    address public rewardPool;
    address public unirouter;

    // Fee constants
    uint constant public MAX_FEE = 1000;
    uint public treasuryFee;
    uint public rewardPoolFee;

    address[] public wNativeToBifiRoute;

    bool public routerInitialized;

    event NewRewardPool(address oldRewardPool, address newRewardPool);
    event NewTreasury(address oldTreasury, address newTreasury);
    event NewUnirouter(address oldUnirouter, address newUnirouter);
    event NewBifiRoute(address[] oldRoute, address[] newRoute);

    function initialize(
        address _bifi,
        address _wNative,
        address _treasury, 
        address _rewardPool, 
        address _unirouter 
    ) public initializer {
        __Ownable_init();

        bifi = IERC20Upgradeable(_bifi);
        wNative  = IERC20Upgradeable(_wNative);
        treasury = _treasury;
        rewardPool = _rewardPool;

        treasuryFee = 140;
        rewardPoolFee = MAX_FEE - treasuryFee;

        if (_unirouter != address(0x0)) {
            _initRouter(_unirouter);
        }
        
        wNativeToBifiRoute = [_wNative, _bifi];
    }

    // Main function. Divides Beefy's profits.
    function harvest() public {
        uint256 wNativeBal = wNative.balanceOf(address(this));

        if (routerInitialized) {
            uint256 treasuryHalf = wNativeBal * treasuryFee / MAX_FEE / 2;
            wNative.safeTransfer(treasury, treasuryHalf);
            IUniswapRouter(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wNativeToBifiRoute, treasury, block.timestamp);
        } else {
            uint256 treasuryAmount = wNativeBal * treasuryFee / MAX_FEE;
            wNative.safeTransfer(treasury, treasuryAmount);
        }

        uint256 rewardPoolAmount = wNativeBal * rewardPoolFee / MAX_FEE;
        wNative.safeTransfer(rewardPool, rewardPoolAmount);
        IRewardPool(rewardPool).notifyRewardAmount(rewardPoolAmount);
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

    function initRouter(address _unirouter) public onlyOwner {
        _initRouter(_unirouter);
    }

    function _initRouter(address _unirouter) internal {
        unirouter = _unirouter;
        wNative.safeApprove(unirouter, type(uint).max);
        routerInitialized = true;
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        require(routerInitialized, "!initialized");

        emit NewUnirouter(unirouter, _unirouter);

        wNative.safeApprove(_unirouter, type(uint).max);
        wNative.safeApprove(unirouter, 0);
        
        unirouter = _unirouter;
    }

    function setNativeToBifiRoute(address[] memory _route) external onlyOwner {
        require(_route[0] == address(wNative), "!wNative");
        require(_route[_route.length - 1] == address(bifi), "!bifi");

        emit NewBifiRoute(wNativeToBifiRoute, _route);
        wNativeToBifiRoute = _route;
    }

    function setTreasuryFee(uint256 _fee) public onlyOwner {
        require(_fee <= MAX_FEE, "!cap");

        treasuryFee = _fee;
        rewardPoolFee = MAX_FEE - treasuryFee;
    }
    
    // Rescue locked funds sent by mistake
    function inCaseTokensGetStuck(address _token, address _recipient) external onlyOwner {
        require(_token != address(wNative), "!safe");

        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(_recipient, amount);
    }

    function transferRewardPoolOwnership(address _newOwner) external onlyOwner {
        IRewardPool(rewardPool).transferOwnership(_newOwner);
    }

    receive() external payable {}
}
