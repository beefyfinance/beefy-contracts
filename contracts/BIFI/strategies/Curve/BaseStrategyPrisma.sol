// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/curve/ICurveRouterV1.sol";
import "../../interfaces/curve/IPrisma.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../Common/BaseAllToNativeStrat.sol";
import "../../utils/UniswapV3Utils.sol";
import "../../utils/UniV3Actions.sol";

contract BaseStrategyPrisma is BaseAllToNativeStrat {

    address public constant curveRouter = 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D;
    IPrismaVault public constant prismaVault = IPrismaVault(0x06bDF212C290473dCACea9793890C5024c7Eb02c);

    address public rewardPool; // prisma reward pool

    CurveRoute[] public curveRewards;

    struct RewardV3 {
        address token;
        bytes toNativePath; // uniswap path
        uint minAmount; // minimum amount to be swapped to native
    }
    RewardV3[] public rewardsV3; // rewards swapped via unirouter

    // uniV3 path swapped via unirouter, or 0 to skip and use native via depositToWant
    bytes public nativeToDepositPath;
    // add liquidity via curveRouter, deposit token should match nativeToDepositPath or be native
    CurveRoute public depositToWant;

    address public prismaReceiver;
    address public boostDelegate;
    uint public maxFeePct;

    function initialize(
        address _want,
        address _rewardPool,
        bytes[] calldata _rewardsV3,
        CurveRoute[] calldata _rewardsToNative,
        Reward[] calldata _rewards,
        CurveRoute calldata _depositToWant,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __BaseStrategy_init(_want, 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, _rewards, _commonAddresses);
        rewardPool = _rewardPool;

        for (uint i; i < _rewardsV3.length; i++) {
            addRewardV3(_rewardsV3[i], 1e17);
        }
        for (uint i; i < _rewardsToNative.length; i++) {
            addReward(_rewardsToNative[i].route, _rewardsToNative[i].swapParams, _rewardsToNative[i].minAmount);
        }

        setDepositToWant(_depositToWant.route, _depositToWant.swapParams, _depositToWant.minAmount);

        // prisma.cvx.eth
        prismaReceiver = 0x8ad7a9e2B3Cd9214f36Cb871336d8ab34DdFdD5b;
        boostDelegate = 0x8ad7a9e2B3Cd9214f36Cb871336d8ab34DdFdD5b;
        maxFeePct = 10000;

        _giveAllowances();
    }

    function _deposit(uint amount) internal override {
        IPrismaRewardPool(rewardPool).deposit(address(this), amount);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            IPrismaRewardPool(rewardPool).withdraw(address(this), amount);
        }
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view override returns (uint256) {
        return IPrismaRewardPool(rewardPool).balanceOf(address(this));
    }

    function rewardsAvailable() external view override returns (uint) {
        return IPrismaRewardPool(rewardPool).claimableReward(address(this));
    }

    function _giveAllowances() internal override {
        uint amount = type(uint).max;
        _approve(want, rewardPool, amount);
        _approve(native, unirouter, amount);
    }

    function _removeAllowances() internal override {
        _approve(want, rewardPool, 0);
        _approve(native, unirouter, 0);
    }

    // is it optimal time to harvest?
    // check pending PRISMA vs remaining claimable amount that will receive max boost (maxBoosted)
    // or new epoch started
    function canHarvest() external view returns (bool) {
        if (boostDelegate == address(0)) return true;
        if (lastHarvest / 1 weeks < block.timestamp / 1 weeks) return true;
        uint pendingPrisma = IPrismaRewardPool(rewardPool).claimableReward(address(this));
        (uint maxBoosted,) = prismaVault.getClaimableWithBoost(boostDelegate);
        return maxBoosted >= pendingPrisma;
    }

    function _claim() internal override {
        address receiver = prismaReceiver == address(0) ? address(this) : prismaReceiver;
        address[] memory rewardPools = new address[](1);
        rewardPools[0] = rewardPool;
        prismaVault.batchClaimRewards(receiver, boostDelegate, rewardPools, 0);
    }

    function _swapRewardsToNative() internal override {
        super._swapRewardsToNative();
        for (uint i; i < curveRewards.length; ++i) {
            uint bal = IERC20(curveRewards[i].route[0]).balanceOf(address(this));
            if (bal > curveRewards[i].minAmount) {
                ICurveRouterV1(curveRouter).exchange(curveRewards[i].route, curveRewards[i].swapParams, bal, 0);
            }
        }
        for (uint i; i < rewardsV3.length; ++i) {
            uint bal = IERC20(rewardsV3[i].token).balanceOf(address(this));
            if (bal > rewardsV3[i].minAmount) {
                UniV3Actions.swapV3(unirouter, rewardsV3[i].toNativePath, bal);
            }
        }
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function _swapNativeToWant() internal override {
        if (nativeToDepositPath.length > 0) {
            uint nativeBal = IERC20(native).balanceOf(address(this));
            UniV3Actions.swapV3(unirouter, nativeToDepositPath, nativeBal);
        }

        uint bal = IERC20(depositToWant.route[0]).balanceOf(address(this));
        if (bal > depositToWant.minAmount) {
            ICurveRouterV1(curveRouter).exchange(depositToWant.route, depositToWant.swapParams, bal, 0);
        }
    }

    function _verifyRewardToken(address token) internal view override {
        require(token != rewardPool, "!rewardPool");
    }

    function setPrismaRewardPool(address _newRewardPool) external onlyOwner {
        _withdraw(balanceOfPool());
        _approve(want, rewardPool, 0);
        _approve(want, _newRewardPool, type(uint).max);
        rewardPool = _newRewardPool;
        deposit();
    }

    function setBoostDelegate(address _receiver, address _boostDelegate, uint _maxFee) public onlyManager {
        prismaReceiver = _receiver;
        boostDelegate = _boostDelegate;
        maxFeePct = _maxFee;
    }

    function setNativeToDepositPath(bytes calldata _nativeToDepositPath) public onlyManager {
        if (_nativeToDepositPath.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_nativeToDepositPath);
            require(route[0] == native, "!native");
        }
        nativeToDepositPath = _nativeToDepositPath;
    }

    function setDepositToWant(address[11] calldata _route, uint[5][5] calldata _swapParams, uint minAmount) public onlyManager {
        address token = _route[0];
        require(token != want, "!want");
        require(token != rewardPool, "!rewardPool");

        depositToWant = CurveRoute(_route, _swapParams, minAmount);
        _approve(token, curveRouter, 0);
        _approve(token, curveRouter, type(uint).max);
    }

    function addReward(address[11] calldata _rewardToNativeRoute, uint[5][5] calldata _swapParams, uint _minAmount) public onlyManager {
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");
        require(token != rewardPool, "!rewardPool");

        curveRewards.push(CurveRoute(_rewardToNativeRoute, _swapParams, _minAmount));
        _approve(token, curveRouter, 0);
        _approve(token, curveRouter, type(uint).max);
    }

    function addRewardV3(bytes calldata _rewardToNativePath, uint _minAmount) public onlyManager {
        address[] memory _rewardToNativeRoute = UniswapV3Utils.pathToRoute(_rewardToNativePath);
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");
        require(token != rewardPool, "!rewardPool");

        rewardsV3.push(RewardV3(token, _rewardToNativePath, _minAmount));
        _approve(token, unirouter, 0);
        _approve(token, unirouter, type(uint).max);
    }

    function resetCurveRewards() external onlyManager {
        delete curveRewards;
    }

    function resetRewardsV3() external onlyManager {
        delete rewardsV3;
    }

    function depositToWantRoute() external view returns (address[11] memory, uint256[5][5] memory, uint) {
        return (depositToWant.route, depositToWant.swapParams, depositToWant.minAmount);
    }

    function curveReward(uint i) external view returns (address[11] memory, uint256[5][5] memory, uint) {
        return (curveRewards[i].route, curveRewards[i].swapParams, curveRewards[i].minAmount);
    }

    function curveRewardsLength() external view returns (uint) {
        return curveRewards.length;
    }

    function rewardV3Route(uint i) external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(rewardsV3[i].toNativePath);
    }

    function rewardsV3Length() external view returns (uint) {
        return rewardsV3.length;
    }

}