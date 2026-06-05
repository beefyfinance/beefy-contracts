// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/common/ISolidlyRouter.sol";

interface IRewardPool {
    function notifyRewardAmount(uint256 amount) external;
    function transferOwnership(address owner) external;
}

contract BeefyFeeBatchV3SolidlyRouter is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public wNative;
    IERC20Upgradeable public bifi;
    IERC20Upgradeable public stable;
    address public treasury;
    address public rewardPool;
    address public unirouter;

    // Fee constants
    uint constant public MAX_FEE = 1000;
    uint public treasuryFee;
    uint public rewardPoolFee;

    ISolidlyRouter.Routes[] public wNativeToBifiRoute;
    ISolidlyRouter.Routes[] public wNativeToStableRoute;

    bool public splitTreasury;

    event NewRewardPool(address oldRewardPool, address newRewardPool);
    event NewTreasury(address oldTreasury, address newTreasury);
    event NewUnirouter(address oldUnirouter, address newUnirouter);

    function initialize(
        address _bifi,
        address _wNative,
        address _stable,
        address _treasury, 
        address _rewardPool, 
        address _unirouter,
        ISolidlyRouter.Routes[] memory _bifiRoute,
        ISolidlyRouter.Routes[] memory _stableRoute,
        bool _splitTreasury, 
        uint256 _treasuryFee 
    ) public initializer {
        __Ownable_init();

        bifi = IERC20Upgradeable(_bifi);
        wNative  = IERC20Upgradeable(_wNative);
        stable = IERC20Upgradeable(_stable);
        treasury = _treasury;
        rewardPool = _rewardPool;

        splitTreasury = _splitTreasury;
        treasuryFee = _treasuryFee;
        rewardPoolFee = MAX_FEE - treasuryFee;

        unirouter = _unirouter;
        wNative.safeApprove(_unirouter, type(uint).max);

        for (uint i; i < _bifiRoute.length; ++i) {
                wNativeToBifiRoute.push(_bifiRoute[i]);
            }

        for (uint i; i < _stableRoute.length; ++i) {
                wNativeToStableRoute.push(_stableRoute[i]);
            }
    }

    // Main function. Divides Beefy's profits.
    function harvest() public {
        uint256 wNativeBal = wNative.balanceOf(address(this));

        if (splitTreasury) {
            uint256 treasuryHalf = wNativeBal * treasuryFee / MAX_FEE / 2;
            ISolidlyRouter(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wNativeToStableRoute, treasury, block.timestamp);
            ISolidlyRouter(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wNativeToBifiRoute, treasury, block.timestamp);
        } else {
            uint256 treasuryAmount = wNativeBal * treasuryFee / MAX_FEE;
            ISolidlyRouter(unirouter).swapExactTokensForTokens(treasuryAmount, 0, wNativeToStableRoute, treasury, block.timestamp);
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

    function setTreasurySplit(bool _split) external onlyOwner {
        splitTreasury = _split;
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        emit NewUnirouter(unirouter, _unirouter);

        wNative.safeApprove(_unirouter, type(uint).max);
        wNative.safeApprove(unirouter, 0);
        
        unirouter = _unirouter;
    }

    function setRoute(ISolidlyRouter.Routes[] memory _route, bool _stableRoute) external onlyOwner {
        require(_route[0].from == address(wNative), "!wNative");
        if(_stableRoute) {
            delete wNativeToStableRoute;
            require(_route[_route.length - 1].to == address(stable), "!stable");
            for (uint i; i < _route.length; ++i) {
                wNativeToStableRoute.push(_route[i]);
            }
        } else {
            delete wNativeToBifiRoute;
            require(_route[_route.length - 1].to == address(bifi), "!BIFI");
             for (uint i; i < _route.length; ++i) {
                wNativeToBifiRoute.push(_route[i]);
            }
        }
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
