// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IRewardPool {
    function notifyRewardAmount(uint256 amount) external;
    function transferOwnership(address owner) external;
}

interface IWrappedNative is IERC20Upgradeable {
    function deposit() external payable;
    function withdraw(uint wad) external;
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

contract BeefyFeeBatchV3 is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public wNative;
    IERC20Upgradeable public bifi;
    IERC20Upgradeable public stable;
    address public treasury;
    address public rewardPool;
    address public unirouter;
    address public harvester;

    // Fee constants
    uint constant public DIVISOR = 1000;
    uint public treasuryFee;
    uint public harvesterGas;
    uint public harvesterMax;
    uint public splitRatio;

    address[] public wNativeToBifiRoute;
    address[] public wNativeToStableRoute;

    bool public splitTreasury;
    bool public sendHarvesterGas;

    event Harvest(uint256 totalHarvested, uint256 stablesHarvested, uint256 bifiHarvested, uint256 nativeNotified, uint256 time);
    event NewRewardPool(address oldRewardPool, address newRewardPool);
    event NewTreasury(address oldTreasury, address newTreasury);
    event NewUnirouter(address oldUnirouter, address newUnirouter);
    event NewTreasuryFee(uint oldFee, uint newFee);
    event NewBifiRoute(address[] oldRoute, address[] newRoute);
    event NewStableRoute(address[] oldRoute, address[] newRoute);
    event TransferedRewardPoolOwnership(address newOwner);
    event SetTreasurySplit(bool split, uint splitRatio);
    event HarvesterConfigUpdate(address harvester, uint harvesterGas, uint harvesterMax, bool sendHarvesterGas);

    function initialize(
        address _bifi,
        address _wNative,
        address _stable,
        address _treasury, 
        address _rewardPool, 
        address _unirouter,
        address[] memory _bifiRoute, 
        address[] memory _stableRoute,
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

        unirouter = _unirouter;
        wNative.safeApprove(_unirouter, type(uint).max);

        wNativeToBifiRoute = _bifiRoute;
        wNativeToStableRoute = _stableRoute;
    }

    // Main function. Divides Beefy's profits.
    function harvest() public {
        uint256 wNativeBal = wNative.balanceOf(address(this));

        if (sendHarvesterGas) {
            uint256 harvesterGasBal = harvester.balance + wNative.balanceOf(harvester);
            if (harvesterGasBal <= harvesterMax) {
                uint256 gas = wNativeBal * harvesterGas / DIVISOR;
                IWrappedNative(address(wNative)).withdraw(gas);
                (bool sent, ) = harvester.call{value: gas}("");
                require(sent, "Failed to send Ether");
            }
            wNativeBal = wNative.balanceOf(address(this));
        }

        uint256 stableAmt;
        uint256 bifiAmt;
        if (splitTreasury) {
            uint256 nativeAvailable = wNativeBal * treasuryFee / DIVISOR;
            stableAmt = nativeAvailable * splitRatio / DIVISOR;
            bifiAmt = nativeAvailable - stableAmt;
            IUniswapRouter(unirouter).swapExactTokensForTokens(stableAmt, 0, wNativeToStableRoute, treasury, block.timestamp);
            IUniswapRouter(unirouter).swapExactTokensForTokens(bifiAmt, 0, wNativeToBifiRoute, treasury, block.timestamp);
        } else {
            stableAmt = wNativeBal * treasuryFee / DIVISOR;
            IUniswapRouter(unirouter).swapExactTokensForTokens(stableAmt, 0, wNativeToStableRoute, treasury, block.timestamp);
        }

        uint256 rewardPoolAmount = wNative.balanceOf(address(this));
        wNative.safeTransfer(rewardPool, rewardPoolAmount);
        IRewardPool(rewardPool).notifyRewardAmount(rewardPoolAmount);

        emit Harvest(wNativeBal, stableAmt, bifiAmt, rewardPoolAmount, block.timestamp);
    }

    function setRewardPool(address _rewardPool) external onlyOwner {
        emit NewRewardPool(rewardPool, _rewardPool);
        rewardPool = _rewardPool;
    }

    function setTreasury(address _treasury) external onlyOwner {
        emit NewTreasury(treasury, _treasury);
        treasury = _treasury;
    }

    function setHarvesterConfig(address _harvester, uint256 _harvesterGas, uint256 _harvesterMax, bool _sendHarvesterGas) external onlyOwner {
        emit HarvesterConfigUpdate(_harvester, _harvesterGas, _harvesterMax, _sendHarvesterGas);
        harvester = _harvester;
        harvesterGas = _harvesterGas;
        sendHarvesterGas = _sendHarvesterGas;
        harvesterMax = _harvesterMax;
    }

    function setTreasurySplit(bool _split, uint _splitRatio) external onlyOwner {
        emit SetTreasurySplit(_split, _splitRatio);
        splitTreasury = _split;
        splitRatio = _splitRatio;
    }

    function setUnirouter(address _unirouter) external onlyOwner {
        emit NewUnirouter(unirouter, _unirouter);

        wNative.safeApprove(_unirouter, type(uint).max);
        wNative.safeApprove(unirouter, 0);
        
        unirouter = _unirouter;
    }

    function setRoute(address[] calldata _route, bool _stableRoute) external onlyOwner {
        require(_route[0] == address(wNative), "!wNative");
        if(_stableRoute) {
            require(_route[_route.length - 1] == address(stable), "!stable");

            emit NewStableRoute(wNativeToStableRoute, _route);
            wNativeToStableRoute = _route;
        } else {
            require(_route[_route.length - 1] == address(bifi), "!bifi");

            emit NewBifiRoute(wNativeToBifiRoute, _route);
            wNativeToBifiRoute = _route;
        }
    }

    function setTreasuryFee(uint256 _fee) public onlyOwner {
        require(_fee <= DIVISOR, "!cap");
        emit NewTreasuryFee(treasuryFee, _fee);
        treasuryFee = _fee;
     }
    
    // Rescue locked funds sent by mistake
    function inCaseTokensGetStuck(address _token, address _recipient) external onlyOwner {
        require(_token != address(wNative), "!safe");

        uint256 amount = IERC20Upgradeable(_token).balanceOf(address(this));
        IERC20Upgradeable(_token).safeTransfer(_recipient, amount);
    }

    function transferRewardPoolOwnership(address _newOwner) external onlyOwner {
        emit TransferedRewardPoolOwnership(_newOwner);
        IRewardPool(rewardPool).transferOwnership(_newOwner);
    }

    receive() external payable {}
}
