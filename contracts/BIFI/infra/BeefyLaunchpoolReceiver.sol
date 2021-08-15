// SPDX-License-Identifier: MIT

pragma solidity ^0.5.0;

import "@openzeppelin-2/contracts/math/SafeMath.sol";
import "@openzeppelin-2/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin-2/contracts/ownership/Ownable.sol";

import "./BeefyLaunchpool.sol";

interface IMooVault {
    function want() external view returns (address);
    function depositAll() external;
}

interface ILaunchpool {
    function rewardToken() external view returns (address);
}

contract BeefyLaunchpoolReceiver is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public lead;
    address public dev;
    address public token;
    address public launchpool;

    uint256 public fee; // 50 = 5%
    uint256 public constant FEE_MAX = 1000;

    event LaunchpoolCreated(address launchpool);

    modifier onlyManager() {
        require(msg.sender == lead || msg.sender == dev || msg.sender == owner(), "!manager");
        _;
    }

    constructor(address _lead, address _dev, address _token, uint256 _fee) public {
        lead = _lead;
        dev = _dev;
        token = _token;
        fee = _fee;
    }

    function setDev(address _dev) external onlyManager {
        dev = _dev;
    }

    function createLaunchpoolMooToken(address _stakedToken, address _rewardMooToken, uint8 _durationDays) external onlyManager {
        _createLaunchPool(_stakedToken, _rewardMooToken, _durationDays);
    }

    function createLaunchpool(address _stakedToken, uint8 _durationDays) external onlyManager {
        _createLaunchPool(_stakedToken, token, _durationDays);
    }

    function _createLaunchPool(address _stakedToken, address _rewardToken, uint8 _durationDays) internal {
        require(launchpool == address(0), "launchpool already set");

        // rewardToken or mooVault.want must be 'token'
        if (_rewardToken != token) {
            address vaultWant = IMooVault(_rewardToken).want();
            require(vaultWant == token, "!token");
        }

        uint256 duration = 3600 * 24 * _durationDays;
        BeefyLaunchpool newLaunchpool = new BeefyLaunchpool(_stakedToken, _rewardToken, duration);
        newLaunchpool.transferOwnership(owner());

        launchpool = address(newLaunchpool);
        emit LaunchpoolCreated(launchpool);
    }

    function sendRewardsToLaunchpool() external onlyOwner {
        require(launchpool != address(0), "!launchpool");
        uint bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, "no rewards");

        uint feeAmount = bal.mul(fee).div(FEE_MAX);
        IERC20(token).safeTransfer(lead, feeAmount);

        address rewardToken = ILaunchpool(launchpool).rewardToken();
        if (rewardToken != token) {
            address vaultWant = IMooVault(rewardToken).want();
            require(vaultWant == token, "!token");

            uint depositBal = IERC20(token).balanceOf(address(this));
            IERC20(token).approve(rewardToken, depositBal);
            IMooVault(rewardToken).depositAll();
        }

        uint rewardBal = IERC20(rewardToken).balanceOf(address(this));
        IERC20(rewardToken).safeTransfer(launchpool, rewardBal);
    }

    function recoverRewards() external onlyManager {
        recover(token);
    }

    function recover(address _token) public onlyManager {
        uint bal = IERC20(_token).balanceOf(address(this));
        recover(_token, bal);
    }

    function recover(address _token, uint _amount) public onlyManager {
        IERC20(_token).safeTransfer(owner(), _amount);
    }
}
