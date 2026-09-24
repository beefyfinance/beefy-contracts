// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Common/BaseAllToNativeFactoryStrat.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../../interfaces/aura/IAuraRewardPool.sol";
import "../../interfaces/aura/IAuraBooster.sol";
import "../../interfaces/beethovenx/IBalancerVault.sol";

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
}

interface IMinter {
    function mint(address gauge) external;
}

// Strategy for Balancer/Aura
contract StrategyBalancer is BaseAllToNativeFactoryStrat {

    uint256 private constant NOT_AURA = 1234567;
    bool private useAura;

    IRewardsGauge public gauge;
    IAuraBooster public booster;
    address public rewardPool;
    IMinter public minter;
    IBalancerVault public balancerVault;
    uint256 public pid;

    function initialize(
        address _gauge,
        address _booster,
        address _balancerVault,
        uint256 _pid,
        address[] calldata _rewards,
        Addresses calldata _commonAddresses
    ) public initializer {
        gauge = IRewardsGauge(_gauge);
        balancerVault = IBalancerVault(_balancerVault);
        booster = IAuraBooster(_booster);
        pid = _pid;
        if (pid != NOT_AURA) useAura = true;

        if (useAura) (,,,rewardPool,,) = booster.poolInfo(pid);
        if (!useAura) minter = IMinter(gauge.bal_pseudo_minter());

        __BaseStrategy_init(_commonAddresses, _rewards);
        _giveAllowances();
    }

    function balanceOfPool() public view override returns (uint bal) {
        if (useAura) return IAuraRewardPool(rewardPool).balanceOf(address(this));
        else return gauge.balanceOf(address(this));
    }

    function stratName() public pure override returns (string memory) {
        return "Balancer";
    }

    function _deposit(uint _amount) internal override {
        if (_amount > 0) {
            if (useAura) booster.deposit(pid, _amount, true);
            else gauge.deposit(_amount);
        } 
    }

    function _withdraw(uint _amount) internal override {
        if (_amount > 0) {
            if (useAura) IAuraRewardPool(rewardPool).withdrawAndUnwrap(_amount, false);
            else gauge.withdraw(_amount);
        }
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        if (useAura) IAuraRewardPool(rewardPool).getReward();
        else {
            if (address(minter) != address(0)) minter.mint(address(this));
            gauge.claim_rewards(address(this));
        }
    }

    function _swapNativeToWant() internal override {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (depositToken != native) IBeefySwapper(swapper).swap(native, depositToken, nativeBal);

        if (depositToken != want) {
            uint256 depositBal = IERC20(depositToken).balanceOf(address(this));
            _balancerJoin( IBalancerPool(want).getPoolId(), depositToken, depositBal);
        }
    }

    function _giveAllowances() internal {
        uint max = type(uint).max;

        if (useAura) _approve(want, address(booster), max);
        else _approve(want, address(gauge), max);
        _approve(native, address(swapper), max);
        if (depositToken != want) _approve(depositToken, address(balancerVault), max);
    }

    function _removeAllowances() internal {
        if (useAura) _approve(want, address(booster), 0);
        else _approve(want, address(gauge), 0);
        _approve(native, address(swapper), 0);
        if (depositToken != want) _approve(depositToken, address(balancerVault), 0);
    }

    function panic() public override onlyManager {
        pause();
        _emergencyWithdraw();
        _removeAllowances();
    }

    function pause() public override onlyManager {
        _pause();
        _removeAllowances();
    }

    function unpause() external override onlyManager {
        _unpause();
        _giveAllowances();
        deposit();
    }

    function setPid(uint256 _pid, address _gauge, address _booster) external onlyOwner {
        _emergencyWithdraw();
        _removeAllowances();
        pid = _pid;
        if (pid == NOT_AURA) gauge = IRewardsGauge(_gauge);
        else (,,,rewardPool,,) = booster.poolInfo(pid);
        if (_booster != address(0)) booster = IAuraBooster(_booster);
        _giveAllowances();
        deposit();
    }


    function _approve(address _token, address _spender, uint amount) internal {
        IERC20(_token).approve(_spender, amount);
    }

     function _balancerJoin(bytes32 _poolId, address _tokenIn, uint256 _amountIn) internal {
        (address[] memory lpTokens,,) = balancerVault.getPoolTokens(_poolId);
        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length;) {
            amounts[i] = lpTokens[i] == _tokenIn ? _amountIn : 0;
            unchecked { ++i; }
        }
        bytes memory userData = abi.encode(1, amounts, 1);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(lpTokens, amounts, userData, false);
        balancerVault.joinPool(_poolId, address(this), address(this), request);
    }

    function _verifyRewardToken(address token) internal view override {}
}
