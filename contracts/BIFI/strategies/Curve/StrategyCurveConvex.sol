// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/convex/IConvex.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../../interfaces/curve/ICrvMinter.sol";
import "../../interfaces/curve/ICurveRouter.sol";
import "../../interfaces/curve/IRewardsGauge.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/UniswapV3Utils.sol";

// Curve L1 strategy switchable between Curve and Convex
contract StrategyCurveConvex is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // this `pid` means we using Curve gauge and not Convex rewardPool
    uint constant public NO_PID = 42069;

    // Tokens used
    address public constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant curveRouter = 0x99a58482BD75cbab83b27EC03CA68fF489b5788f;
    IConvexBooster public constant booster = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    ICrvMinter public constant minter = ICrvMinter(0xd061D61a4d941c39E5453435B6345Dc261C2fcE0);

    address public want; // curve lpToken
    address public gauge; // curve gauge
    address public rewardPool; // convex base reward pool
    uint public pid; // convex booster poolId

    struct CurveRoute {
        address[9] route;
        uint256[3][4] swapParams;
        uint minAmount; // minimum amount to be swapped to native
    }
    CurveRoute[] public curveRewards;

    struct RewardV3 {
        address token;
        bytes toNativePath; // uniswap path
        uint minAmount; // minimum amount to be swapped to native
    }
    RewardV3[] public rewardsV3; // rewards swapped via unirouter

    struct RewardV2 {
        address token;
        address router; // uniswap v2 router
        address[] toNativeRoute; // uniswap route
        uint minAmount; // minimum amount to be swapped to native
    }
    RewardV2[] public rewardsV2;

    // uniV3 path swapped via unirouter, or 0 to skip and use native via depositToWant
    bytes public nativeToDepositPath;
    // add liquidity via curveRouter, deposit token should match nativeToDepositPath or be native
    CurveRoute public depositToWant;

    bool public isCrvMintable; // if CRV can be minted via Minter (gauge is added to Controller)
    bool public skipEarmarkRewards;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _gauge,
        uint _pid,
        bytes calldata _crvToNativePath,
        bytes calldata _cvxToNativePath,
        bytes calldata _nativeToDepositPath,
        CurveRoute calldata _depositToWant,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        gauge = _gauge;
        pid = _pid;

        if (_pid != NO_PID) {
            (,,, rewardPool,,) = booster.poolInfo(_pid);
        }

        if (_crvToNativePath.length > 0) addRewardV3(_crvToNativePath, 1e18);
        if (_cvxToNativePath.length > 0) addRewardV3(_cvxToNativePath, 1e18);

        setNativeToDepositPath(_nativeToDepositPath);
        setDepositToWant(_depositToWant.route, _depositToWant.swapParams, _depositToWant.minAmount);

        withdrawalFee = 1;
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            if (rewardPool != address(0)) {
                booster.deposit(pid, wantBal, true);
            } else {
                IRewardsGauge(gauge).deposit(wantBal);
            }
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
            if (rewardPool != address(0)) {
                IConvexRewardPool(rewardPool).withdrawAndUnwrap(_amount, false);
            } else {
                IRewardsGauge(gauge).withdraw(_amount);
            }
        }
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
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
            if (!onDeposit) {
                deposit();
            }
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _claim() internal {
        if (rewardPool != address(0)) {
            if (!skipEarmarkRewards && IConvexRewardPool(rewardPool).periodFinish() < block.timestamp) {
                booster.earmarkRewards(pid);
            }
            IConvexRewardPool(rewardPool).getReward();
        } else {
            if (isCrvMintable) minter.mint(gauge);
            IRewardsGauge(gauge).claim_rewards(address(this));
        }
    }

    function _swapRewardsToNative() internal {
        for (uint i; i < curveRewards.length; ++i) {
            uint bal = IERC20(curveRewards[i].route[0]).balanceOf(address(this));
            if (bal >= curveRewards[i].minAmount) {
                ICurveRouter(curveRouter).exchange_multiple(curveRewards[i].route, curveRewards[i].swapParams, bal, 0);
            }
        }
        for (uint i; i < rewardsV2.length; ++i) {
            uint bal = IERC20(rewardsV2[i].token).balanceOf(address(this));
            if (bal >= rewardsV2[i].minAmount) {
                IUniswapRouterETH(rewardsV2[i].router).swapExactTokensForTokens(bal, 0, rewardsV2[i].toNativeRoute, address(this), block.timestamp);
            }
        }
        for (uint i; i < rewardsV3.length; ++i) {
            uint bal = IERC20(rewardsV3[i].token).balanceOf(address(this));
            if (bal >= rewardsV3[i].minAmount) {
                UniswapV3Utils.swap(unirouter, rewardsV3[i].toNativePath, bal);
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
            UniswapV3Utils.swap(unirouter, nativeToDepositPath, nativeBal);
        }

        uint bal = IERC20(depositToWant.route[0]).balanceOf(address(this));
        ICurveRouter(curveRouter).exchange_multiple(depositToWant.route, depositToWant.swapParams, bal, 0);
    }

    function setConvexPid(uint _pid) external onlyOwner {
        _withdraw(balanceOfPool());
        if (_pid != NO_PID) {
            (,,,rewardPool,,) = booster.poolInfo(_pid);
        } else {
            rewardPool = address(0);
        }
        pid = _pid;
        deposit();
    }

    function setNativeToDepositPath(bytes calldata _nativeToDepositPath) public onlyOwner {
        if (_nativeToDepositPath.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_nativeToDepositPath);
            require(route[0] == native, "!native");
        }
        nativeToDepositPath = _nativeToDepositPath;
    }

    function setDepositToWant(address[9] calldata _route, uint[3][4] calldata _swapParams, uint minAmount) public onlyOwner {
        address token = _route[0];
        require(token != want, "!want");

        depositToWant = CurveRoute(_route, _swapParams, minAmount);
        _approve(token, curveRouter, 0);
        _approve(token, curveRouter, type(uint).max);
    }

    function addReward(address[9] calldata _rewardToNativeRoute, uint[3][4] calldata _swapParams, uint _minAmount) external onlyOwner {
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");

        curveRewards.push(CurveRoute(_rewardToNativeRoute, _swapParams, _minAmount));
        _approve(token, curveRouter, 0);
        _approve(token, curveRouter, type(uint).max);
    }

    function addRewardV2(address _router, address[] calldata _rewardToNativeRoute, uint _minAmount) external onlyOwner {
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");

        rewardsV2.push(RewardV2(token, _router, _rewardToNativeRoute, _minAmount));
        IERC20(token).approve(_router, 0);
        IERC20(token).approve(_router, type(uint).max);
    }

    function addRewardV3(bytes calldata _rewardToNativePath, uint _minAmount) public onlyOwner {
        address[] memory _rewardToNativeRoute = UniswapV3Utils.pathToRoute(_rewardToNativePath);
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");

        rewardsV3.push(RewardV3(token, _rewardToNativePath, _minAmount));
        _approve(token, unirouter, 0);
        _approve(token, unirouter, type(uint).max);
    }

    function resetCurveRewards() external onlyManager {
        delete curveRewards;
    }

    function resetRewardsV2() external onlyManager {
        delete rewardsV2;
    }

    function resetRewardsV3() external onlyManager {
        delete rewardsV3;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        if (rewardPool != address(0)) {
            return IConvexRewardPool(rewardPool).balanceOf(address(this));
        } else {
            return IRewardsGauge(gauge).balanceOf(address(this));
        }
    }

    function depositToWantRoute() external view returns (address[9] memory, uint256[3][4] memory, uint) {
        return (depositToWant.route, depositToWant.swapParams, depositToWant.minAmount);
    }

    function curveReward(uint i) external view returns (address[9] memory, uint256[3][4] memory, uint) {
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

    function rewardV2(uint i) external view returns (address, address[] memory, uint) {
        return (rewardsV2[i].router, rewardsV2[i].toNativeRoute, rewardsV2[i].minAmount);
    }

    function rewardsV2Length() external view returns (uint) {
        return rewardsV2.length;
    }

    function setCrvMintable(bool _isCrvMintable) external onlyManager {
        isCrvMintable = _isCrvMintable;
    }

    function setSkipEarmarkRewards(bool _skipEarmarkRewards) external onlyManager {
        skipEarmarkRewards = _skipEarmarkRewards;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(1);
        }
    }

    function rewardsAvailable() external view returns (uint) {
        if (rewardPool != address(0)) {
            return IConvexRewardPool(rewardPool).earned(address(this));
        }
        return 0;
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
        _approve(want, address(gauge), amount);
        _approve(want, address(booster), amount);
        _approve(native, unirouter, amount);
    }

    function _removeAllowances() internal {
        _approve(want, address(gauge), 0);
        _approve(want, address(booster), 0);
        _approve(native, unirouter, 0);
    }

    function _approve(address _token, address _spender, uint amount) internal {
        IERC20(_token).approve(_spender, amount);
    }

    receive () external payable {}
}
