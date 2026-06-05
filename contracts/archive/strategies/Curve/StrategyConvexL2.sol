// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/convex/IConvex.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../../interfaces/curve/IGaugeFactory.sol";
import "../Common/StratFeeManager.sol";
import "../../utils/Path.sol";
import "../../utils/UniV3Actions.sol";

contract StrategyConvexL2 is StratFeeManager {
    using Path for bytes;
    using SafeERC20 for IERC20;

    IConvexBoosterL2 public constant booster = IConvexBoosterL2(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
    address public constant unirouterV3 = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public native;

    address public want; // curve lpToken
    address public pool; // curve swap pool
    address public zap; // curve zap to deposit in metapools, or 0
    address public depositToken; // token sent to pool or zap to receive want
    address public rewardPool; // convex base reward pool
    uint public pid; // convex booster poolId
    uint public poolSize; // pool or zap size
    uint public depositIndex; // index of depositToken in pool or zap
    bool public useUnderlying; // pass additional true to add_liquidity e.g. aave tokens
    bool public depositNative; // if depositToken should be sent as unwrapped native

    // v3 path or v2 route swapped via StratFeeManager.unirouter
    bytes public nativeToDepositPath;
    address[] public nativeToDepositRoute;

    struct RewardV3 {
        address token;
        bytes toNativePath; // uniswap path
        uint minAmount; // minimum amount to be swapped to native
    }
    RewardV3[] public rewardsV3; // rewards swapped via unirouterV3

    struct RewardV2 {
        address token;
        address router; // uniswap v2 router
        address[] toNativeRoute; // uniswap route
        uint minAmount; // minimum amount to be swapped to native
    }
    RewardV2[] public rewards;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        address _pool,
        address _zap,
        uint _pid,
        uint[] memory _params, // [poolSize, depositIndex, useUnderlying, useDepositNative]
        bytes memory _crvToNativePath,
        bytes memory _cvxToNativePath,
        bytes memory _nativeToDepositPath,
        address[] memory _nativeToDepositRoute,
        CommonAddresses memory _commonAddresses
    ) StratFeeManager(_commonAddresses) {
        want = _want;
        pool = _pool;
        zap = _zap;
        pid = _pid;
        poolSize = _params[0];
        depositIndex = _params[1];
        useUnderlying = _params[2] > 0;
        depositNative = _params[3] > 0;
        (,,rewardPool,,) = booster.poolInfo(_pid);

        if (_nativeToDepositPath.length > 0) {
            address[] memory nativeRoute = pathToRoute(_nativeToDepositPath);
            native = nativeRoute[0];
            depositToken = nativeRoute[nativeRoute.length - 1];
            nativeToDepositPath = _nativeToDepositPath;
        } else {
            native = _nativeToDepositRoute[0];
            depositToken = _nativeToDepositRoute[_nativeToDepositRoute.length - 1];
            nativeToDepositRoute = _nativeToDepositRoute;
        }
        if (_crvToNativePath.length > 0) addRewardV3(_crvToNativePath, 1e18);
        if (_cvxToNativePath.length > 0) addRewardV3(_cvxToNativePath, 1e18);

        withdrawalFee = 0;
        harvestOnDeposit = true;
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            booster.deposit(pid, wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IConvexRewardPool(rewardPool).withdraw(_amount - wantBal, false);
            wantBal = IERC20(want).balanceOf(address(this));
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
        IConvexRewardPool(rewardPool).getReward(address(this));
        swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            if (!onDeposit) {
                deposit();
            }
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function swapRewardsToNative() internal {
        for (uint i; i < rewardsV3.length; ++i) {
            uint bal = IERC20(rewardsV3[i].token).balanceOf(address(this));
            if (bal >= rewardsV3[i].minAmount) {
                UniV3Actions.swapV3WithDeadline(unirouterV3, rewardsV3[i].toNativePath, bal);
            }
        }
        for (uint i; i < rewards.length; ++i) {
            uint bal = IERC20(rewards[i].token).balanceOf(address(this));
            if (bal >= rewards[i].minAmount) {
                IUniswapRouterETH(rewards[i].router).swapExactTokensForTokens(bal, 0, rewards[i].toNativeRoute, address(this), block.timestamp);
            }
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
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
    function addLiquidity() internal {
        uint256 depositBal;
        uint256 depositNativeAmount;
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (depositToken != native) {
            if (nativeToDepositPath.length > 0) {
                UniV3Actions.swapV3WithDeadline(unirouter, nativeToDepositPath, nativeBal);
            } else {
                IUniswapRouterETH(unirouter).swapExactTokensForTokens(nativeBal, 0, nativeToDepositRoute, address(this), block.timestamp);
            }
            depositBal = IERC20(depositToken).balanceOf(address(this));
        } else {
            depositBal = nativeBal;
            if (depositNative) {
                depositNativeAmount = nativeBal;
                IWrappedNative(native).withdraw(depositNativeAmount);
            }
        }

        if (poolSize == 2) {
            uint256[2] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else ICurveSwap(pool).add_liquidity{value: depositNativeAmount}(amounts, 0);
        } else if (poolSize == 3) {
            uint256[3] memory amounts;
            amounts[depositIndex] = depositBal;
            if (useUnderlying) ICurveSwap(pool).add_liquidity(amounts, 0, true);
            else if (zap != address(0)) ICurveSwap(zap).add_liquidity{value: depositNativeAmount}(pool, amounts, 0);
            else ICurveSwap(pool).add_liquidity{value: depositNativeAmount}(amounts, 0);
        } else if (poolSize == 4) {
            uint256[4] memory amounts;
            amounts[depositIndex] = depositBal;
            if (zap != address(0)) ICurveSwap(zap).add_liquidity(pool, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 5) {
            uint256[5] memory amounts;
            amounts[depositIndex] = depositBal;
            if (zap != address(0)) ICurveSwap(zap).add_liquidity(pool, amounts, 0);
            else ICurveSwap(pool).add_liquidity(amounts, 0);
        }
    }

    function addRewardV2(address _router, address[] calldata _rewardToNativeRoute, uint _minAmount) external onlyOwner {
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");
        require(token != rewardPool, "!convex");

        rewards.push(RewardV2(token, _router, _rewardToNativeRoute, _minAmount));
        IERC20(token).approve(_router, 0);
        IERC20(token).approve(_router, type(uint).max);
    }

    function addRewardV3(bytes memory _rewardToNativePath, uint _minAmount) public onlyOwner {
        address[] memory _rewardToNativeRoute = pathToRoute(_rewardToNativePath);
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");
        require(token != rewardPool, "!convex");

        rewardsV3.push(RewardV3(token, _rewardToNativePath, _minAmount));
        IERC20(token).approve(unirouterV3, 0);
        IERC20(token).approve(unirouterV3, type(uint).max);
    }

    function resetRewardsV2() external onlyManager {
        delete rewards;
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
        return IConvexRewardPool(rewardPool).balanceOf(address(this));
    }

    function pathToRoute(bytes memory _path) public pure returns (address[] memory) {
        uint numPools = _path.numPools();
        address[] memory route = new address[](numPools + 1);
        for (uint i; i < numPools; i++) {
            (address tokenA, address tokenB,) = _path.decodeFirstPool();
            route[i] = tokenA;
            route[i + 1] = tokenB;
            _path = _path.skipToken();
        }
        return route;
    }

    function nativeToDeposit() external view returns (address[] memory) {
        if (nativeToDepositPath.length > 0) {
            return pathToRoute(nativeToDepositPath);
        } else return nativeToDepositRoute;
    }

    function rewardV3ToNative() external view returns (address[] memory) {
        return pathToRoute(rewardsV3[0].toNativePath);
    }

    function rewardV3ToNative(uint i) external view returns (address[] memory) {
        return pathToRoute(rewardsV3[i].toNativePath);
    }

    function rewardsV3Length() external view returns (uint) {
        return rewardsV3.length;
    }

    function rewardToNative() external view returns (address[] memory) {
        return rewards[0].toNativeRoute;
    }

    function rewardToNative(uint i) external view returns (address[] memory) {
        return rewards[i].toNativeRoute;
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    function setDepositNative(bool _depositNative) external onlyOwner {
        depositNative = _depositNative;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(1);
        }
    }

    // returns rewards unharvested
    function rewardsAvailable() public pure returns (uint256) {
        return 0;
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IConvexRewardPool(rewardPool).emergencyWithdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IConvexRewardPool(rewardPool).emergencyWithdraw(balanceOfPool());
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
        IERC20(want).approve(address(booster), type(uint).max);
        IERC20(native).approve(unirouter, type(uint).max);
        IERC20(depositToken).approve(pool, type(uint).max);
        if (zap != address(0)) IERC20(depositToken).approve(zap, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).approve(address(booster), 0);
        IERC20(native).approve(unirouter, 0);
        IERC20(depositToken).approve(pool, 0);
        if (zap != address(0)) IERC20(depositToken).approve(zap, 0);
    }

    receive () external payable {}
}
