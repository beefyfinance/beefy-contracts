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
import "../../interfaces/curve/IConic.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/UniswapV3Utils.sol";

contract StrategyConic is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // this `pid` means we using Curve gauge and not Convex rewardPool
    uint constant public NO_PID = 42069;

    // Tokens used
    address public constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant cnc = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;
    address public constant cncEthPool = 0x838af967537350D2C44ABB8c010E49E32673ab94;
    address public constant curveRouter = 0x99a58482BD75cbab83b27EC03CA68fF489b5788f;
    ILpTokenStaker public constant lpStaker = ILpTokenStaker(0xeC037423A61B634BFc490dcc215236349999ca3d);

    address public want; // conic lpToken
    address public conicPool; // conic omnipool
    address public underlying; // token deposited into conic omnipool to build conic lpToken (want)
    IRewardManager public rewardManager;

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

    // uniV3 path swapped via unirouter, or 0 to skip and use swap via curveRouter
    bytes public nativeToUnderlyingPath;
    // swap via curveRouter, used if nativeToUnderlyingPath is 0
    CurveRoute public nativeToUnderlying;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        bytes calldata _crvToNativePath,
        bytes calldata _cvxToNativePath,
        bytes calldata _nativeToUnderlyingPath,
        CurveRoute calldata _nativeToUnderlying,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        conicPool = ILpToken(_want).minter();
        rewardManager = IConicPool(conicPool).rewardManager();
        underlying = IConicPool(conicPool).underlying();

        if (_crvToNativePath.length > 0) addRewardV3(_crvToNativePath, 1e18);
        if (_cvxToNativePath.length > 0) addRewardV3(_cvxToNativePath, 1e18);
        addReward(
            [cnc, cncEthPool, native, address(0), address(0), address(0), address(0), address(0), address(0)],
            [[uint(1),uint(0),uint(3)], [uint(0),uint(0),uint(0)], [uint(0),uint(0),uint(0)], [uint(0),uint(0),uint(0)]],
            0);

        setNativeToUnderlyingPath(_nativeToUnderlyingPath);
        setNativeToUnderlyingRoute(_nativeToUnderlying.route, _nativeToUnderlying.swapParams, _nativeToUnderlying.minAmount);

        withdrawalFee = 1;
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            lpStaker.stake(wantBal, conicPool);
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
            lpStaker.unstake(_amount, conicPool);
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
        uint256 nativeBal = _balanceOfThis(native);
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
        rewardManager.claimEarnings();
    }

    function _swapRewardsToNative() internal {
        for (uint i; i < curveRewards.length; ++i) {
            uint bal = _balanceOfThis(curveRewards[i].route[0]);
            if (bal >= curveRewards[i].minAmount) {
                ICurveRouter(curveRouter).exchange_multiple(curveRewards[i].route, curveRewards[i].swapParams, bal, 0);
            }
        }
        for (uint i; i < rewardsV3.length; ++i) {
            uint bal = _balanceOfThis(rewardsV3[i].token);
            if (bal >= rewardsV3[i].minAmount) {
                UniswapV3Utils.swap(unirouter, rewardsV3[i].toNativePath, bal);
            }
        }
    }

    // performance fees
    function _chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = _balanceOfThis(native) * fees.total / DIVISOR;

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
        uint nativeBal = _balanceOfThis(native);
        if (nativeToUnderlyingPath.length > 0) {
            UniswapV3Utils.swap(unirouter, nativeToUnderlyingPath, nativeBal);
        } else {
            ICurveRouter(curveRouter).exchange_multiple(nativeToUnderlying.route, nativeToUnderlying.swapParams, nativeBal, 0);
        }

        uint bal = _balanceOfThis(underlying);
        if (bal > 0) {
            IConicPool(conicPool).deposit(bal, 0, false);
        }
    }

    function setNativeToUnderlyingPath(bytes calldata _nativeToUnderlyingPath) public onlyOwner {
        if (_nativeToUnderlyingPath.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_nativeToUnderlyingPath);
            require(route[0] == native, "!native");
        }
        nativeToUnderlyingPath = _nativeToUnderlyingPath;
    }

    function setNativeToUnderlyingRoute(address[9] calldata _route, uint[3][4] calldata _swapParams, uint minAmount) public onlyOwner {
        address token = _route[0];
        require(token == native, "!native");

        nativeToUnderlying = CurveRoute(_route, _swapParams, minAmount);
        _approve(token, curveRouter, 0);
        _approve(token, curveRouter, type(uint).max);
    }

    function addReward(address[9] memory _rewardToNativeRoute, uint[3][4] memory _swapParams, uint _minAmount) public onlyOwner {
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");

        curveRewards.push(CurveRoute(_rewardToNativeRoute, _swapParams, _minAmount));
        _approve(token, curveRouter, 0);
        _approve(token, curveRouter, type(uint).max);
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

    function resetRewardsV3() external onlyManager {
        delete rewardsV3;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return _balanceOfThis(want);
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        return lpStaker.getUserBalanceForPool(conicPool, address(this));
    }

    function nativeToUnderlyingRoute() external view returns (address[9] memory, uint256[3][4] memory, uint) {
        return (nativeToUnderlying.route, nativeToUnderlying.swapParams, nativeToUnderlying.minAmount);
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

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(1);
        }
    }

    function rewardsAvailable() external view returns (uint cncRewards) {
        (cncRewards,,) = rewardManager.claimableRewards(address(this));
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
        _approve(underlying, conicPool, amount);
        _approve(want, address(lpStaker), amount);
        _approve(native, unirouter, amount);
    }

    function _removeAllowances() internal {
        _approve(underlying, conicPool, 0);
        _approve(want, address(lpStaker), 0);
        _approve(native, unirouter, 0);
    }

    function _approve(address _token, address _spender, uint amount) private {
        IERC20(_token).approve(_spender, amount);
    }

    function _balanceOfThis(address _token) private view returns (uint) {
        return IERC20(_token).balanceOf(address(this));
    }

    receive () external payable {}
}
