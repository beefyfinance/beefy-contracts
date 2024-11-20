// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../Common/BaseAllToNativeFactoryStrat.sol";

import "../../interfaces/compound/IComet.sol";
import "../../interfaces/compound/ICometRewards.sol";

contract StrategyCompoundV3 is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    address public cToken;
    address public distributor;

    function initialize(
        address _cToken,
        address _distributor,
        Addresses memory _addresses
    ) external initializer {
        cToken = _cToken;
        distributor = _distributor;

        if(_addresses.want == address(0)) _addresses.want = IComet(_cToken).baseToken();
        address[] memory rewardTokens = new address[](1);
        (address reward,,,) = ICometRewards(distributor).rewardConfig(cToken);
        rewardTokens[0] = reward;
        
        __BaseStrategy_init(_addresses, rewardTokens);
    }

    function stratName() public pure override returns (string memory) {
        return "CompoundV3";
    }

    function balanceOfPool() public view override returns (uint256) {
        return IERC20(cToken).balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(cToken, amount);
        IComet(cToken).supply(want, amount);
    }

    function _withdraw(uint amount) internal override {
        uint256 cTokenBal = IERC20(want).balanceOf(cToken);
        require(cTokenBal >= amount, "Not Enough Underlying");
        IComet(cToken).withdraw(want, amount);
    }

    function _emergencyWithdraw() internal override {
        uint256 bal = IERC20(cToken).balanceOf(address(this));
        if (bal > 0) IComet(cToken).withdraw(want, bal);
    }

    function _claim() internal override {
        ICometRewards(distributor).claim(cToken, address(this), true);
    }

    function _verifyRewardToken(address _token) internal view override {
        require(_token != cToken, "!cToken");
    }
}