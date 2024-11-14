// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Common/BaseAllToNativeFactoryStrat.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../../interfaces/aura/IAuraRewardPool.sol";
import "../../interfaces/curve/IStreamer.sol";
import "../../interfaces/aura/IAuraBooster.sol";
import "../../interfaces/beethovenx/IBalancerVault.sol";

interface IBalancerPool {
    function getPoolId() external view returns (bytes32);
    function getTokenRates() external view returns (uint256, uint256);
}

interface IMinter {
    function mint(address gauge) external;
}

// Strategy for Balancer/Aura
contract StrategyBalancerGyro is BaseAllToNativeFactoryStrat {

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
        if (!useAura)  minter = IMinter(gauge.bal_pseudo_minter());

        __BaseStrategy_init(_commonAddresses, _rewards);
        _giveAllowances();
    }

    function balanceOfPool() public view override returns (uint) {
        if (useAura) return IAuraRewardPool(rewardPool).balanceOf(address(this));
        else return gauge.balanceOf(address(this));
    }

    function stratName() public pure override returns (string memory) {
        return "BalancerGryo";
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
            try minter.mint(address(this)) { /* yay there is rewards */}
            catch { /* If we are here there is no bal */ }
            gauge.claim_rewards(address(this));
        }
    }

    function _swapNativeToWant() internal override {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        bytes32 poolId = IBalancerPool(want).getPoolId();
        (address[] memory lpTokens,,) = balancerVault.getPoolTokens(poolId);
        if (depositToken != native) IBeefySwapper(swapper).swap(native, depositToken, nativeBal);

        if (nativeBal > 0) {
            uint256 lp0Bal = IERC20(lpTokens[0]).balanceOf(address(this));
            (uint256 lp0Amt, uint256 lp1Amt) =  _calcSwapAmount(lp0Bal);

            if (lp0Bal > 0) IBeefySwapper(swapper).swap(lpTokens[0], lpTokens[1], lp1Amt);
            _multiJoin(want, poolId, lpTokens[0], lpTokens[1], lp0Amt, IERC20(lpTokens[1]).balanceOf(address(this)));
        }
    }

    function _calcSwapAmount(uint256 _bal) private view returns (uint256 lp0Amt, uint256 lp1Amt) {
            lp0Amt = _bal / 2;
            lp1Amt = _bal - lp0Amt;

            (uint256 rate0, uint256 rate1) = IBalancerPool(want).getTokenRates();

            (, uint256[] memory balances,) = balancerVault.getPoolTokens(IBalancerPool(want).getPoolId());
            uint256 supply = IERC20(want).totalSupply();

            uint256 amountA = balances[0] * 1e18 / supply;
            uint256 amountB = balances[1] * 1e18 / supply;
            
            uint256 ratio = rate0 * 1e18 / rate1 * amountB / amountA;
            lp0Amt = _bal * 1e18 / (ratio + 1e18);
            lp1Amt = _bal - lp0Amt;
    }

    function _giveAllowances() internal {
        uint max = type(uint).max;
        bytes32 poolId = IBalancerPool(want).getPoolId();
        (address[] memory lpTokens,,) = balancerVault.getPoolTokens(poolId);

        if (useAura) _approve(want, address(booster), max);
        else _approve(want, address(gauge), max);
        _approve(native, address(swapper), max);
        _approve(lpTokens[0], address(swapper), max);
        _approve(lpTokens[0], address(balancerVault), max);
        _approve(lpTokens[1], address(balancerVault), max);

        if (depositToken != want) _approve(depositToken, address(balancerVault), max);
    }

    function _removeAllowances() internal {
        bytes32 poolId = IBalancerPool(want).getPoolId();
        (address[] memory lpTokens,,) = balancerVault.getPoolTokens(poolId);

        if (useAura) _approve(want, address(booster), 0);
        else _approve(want, address(gauge), 0);
        _approve(native, address(swapper), 0);
        _approve(lpTokens[0], address(swapper), 0);
        _approve(lpTokens[0], address(balancerVault), 0);
        _approve(lpTokens[1], address(balancerVault), 0);

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

    function _multiJoin(address _want, bytes32 _poolId, address _token0In, address _token1In, uint256 _amount0In, uint256 _amount1In) internal {
        (address[] memory lpTokens,uint256[] memory balances,) = balancerVault.getPoolTokens(_poolId);
        uint256 supply = IERC20(_want).totalSupply();
        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length;) {
            if (lpTokens[i] == _token0In) amounts[i] = _amount0In;
            else if (lpTokens[i] == _token1In) amounts[i] = _amount1In;
            else amounts[i] = 0;
            unchecked { ++i; }
        }

        uint256 bpt0 = (amounts[0] * supply / balances[0]) - 100;
        uint256 bpt1 = (amounts[1] * supply / balances[1]) - 100;

        uint256 bptOut = bpt0 > bpt1 ? bpt1 : bpt0;
        bytes memory userData = abi.encode(3, bptOut);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(lpTokens, amounts, userData, false);
        balancerVault.joinPool(_poolId, address(this), address(this), request);
    }

    function _verifyRewardToken(address token) internal view override {}
}
