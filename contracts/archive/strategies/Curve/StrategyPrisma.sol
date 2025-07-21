// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/curve/ICurveRouterV1.sol";
import "../../interfaces/curve/IPrisma.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/UniswapV3Utils.sol";
import "../../utils/UniV3Actions.sol";

contract StrategyPrisma is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant curveRouter = 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D;
    IPrismaVault public constant prismaVault = IPrismaVault(0x06bDF212C290473dCACea9793890C5024c7Eb02c);

    address public want; // curve lpToken
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

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public constant DURATION = 1 days;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _rewardPool,
        bytes[] calldata _rewardsV3,
        CurveRoute[] calldata _rewardsToNative,
        CurveRoute calldata _depositToWant,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
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

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IPrismaRewardPool(rewardPool).deposit(address(this), wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            _withdraw(_amount - wantBal);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function _withdraw(uint256 _amount) internal {
        if (_amount > 0) {
            IPrismaRewardPool(rewardPool).withdraw(address(this), _amount);
        }
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
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

    function harvest() external virtual {
        _harvest(tx.origin, false);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient, false);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient, bool onDeposit) internal whenNotPaused {
        _claim();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            _chargeFees(callFeeRecipient);
            _addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;

            if (!onDeposit) {
                deposit();
            }

            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _claim() internal {
        address receiver = prismaReceiver == address(0) ? address(this) : prismaReceiver;
        address[] memory rewardPools = new address[](1);
        rewardPools[0] = rewardPool;
        prismaVault.batchClaimRewards(receiver, boostDelegate, rewardPools, 0);
    }

    function _swapRewardsToNative() internal {
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

    // performance fees
    function _chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function _addLiquidity() internal {
        if (nativeToDepositPath.length > 0) {
            uint nativeBal = IERC20(native).balanceOf(address(this));
            UniV3Actions.swapV3(unirouter, nativeToDepositPath, nativeBal);
        }

        uint bal = IERC20(depositToWant.route[0]).balanceOf(address(this));
        if (bal > depositToWant.minAmount) {
            ICurveRouterV1(curveRouter).exchange(depositToWant.route, depositToWant.swapParams, bal, 0);
        }
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

    function lockedProfit() public view returns (uint256) {
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < DURATION ? DURATION - elapsed : 0;
        return totalLocked * remaining / DURATION;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return IPrismaRewardPool(rewardPool).balanceOf(address(this));
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

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function rewardsAvailable() external view returns (uint) {
        return IPrismaRewardPool(rewardPool).claimableReward(address(this));
    }

    function callReward() external pure returns (uint) {
        return 0;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _withdraw(balanceOfPool());
        IERC20(want).transfer(vault, balanceOfWant());
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        _withdraw(balanceOfPool());
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        deposit();
    }

    function _giveAllowances() internal {
        uint amount = type(uint).max;
        _approve(want, rewardPool, amount);
        _approve(native, unirouter, amount);
    }

    function _removeAllowances() internal {
        _approve(want, rewardPool, 0);
        _approve(native, unirouter, 0);
    }

    function _approve(address _token, address _spender, uint amount) internal {
        IERC20(_token).approve(_spender, amount);
    }
}