// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../interfaces/curve/IRewardsGauge.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

interface IStakeDAOVault {
    function sdGauge() external view returns (address);
    function deposit(address _user, uint256 _amount) external;
    function withdraw(uint256 _amount) external;
}

contract StrategyStakeDao is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    address public sdVault;
    address public sdGauge;

    function initialize(
        address _sdVault,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        sdVault = _sdVault;
        sdGauge = IStakeDAOVault(sdVault).sdGauge();

        __BaseStrategy_init(_addresses, _rewards);
        setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "StrategyStakeDao";
    }

    function balanceOfPool() public view override returns (uint) {
        return IRewardsGauge(sdGauge).balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(sdVault, amount);
        IStakeDAOVault(sdVault).deposit(address(this), amount);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            IStakeDAOVault(sdVault).withdraw(amount);
        }
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        IRewardsGauge(sdGauge).claim_rewards(address(this));
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != sdVault, "!sdVault");
        require(token != sdGauge, "!sdGauge");
    }

}
