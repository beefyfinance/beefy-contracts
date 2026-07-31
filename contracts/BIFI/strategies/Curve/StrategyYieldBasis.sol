// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../Common/BaseAllToNativeFactoryStrat.sol";

interface IYBGauge {
    function claim() external returns (uint);
    function claim(address) external returns (uint);
}

contract StrategyYieldBasis is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    address[] public extraRewards;

    function initialize(address[] calldata _rewards, Addresses calldata _addresses) public initializer {
        __BaseStrategy_init(_addresses, _rewards);
    }

    function stratName() public pure override returns (string memory) {
        return "YieldBasis";
    }

    function balanceOfPool() public pure override returns (uint) {
        return 0;
    }

    function _deposit(uint amount) internal override {}

    function _withdraw(uint amount) internal override {}

    function _emergencyWithdraw() internal override {}

    function _claim() internal override {
        IYBGauge(want).claim();
        for (uint i; i < extraRewards.length; ++i) {
            IYBGauge(want).claim(extraRewards[i]);
        }
    }

    function _verifyRewardToken(address token) internal view override {}

    function setExtraRewards(address[] calldata rewards) external onlyManager {
        extraRewards = rewards;
    }

}
