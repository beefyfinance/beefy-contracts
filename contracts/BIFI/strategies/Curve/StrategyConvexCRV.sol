// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/convex/IStakedCvxCrv.sol";
import "../../interfaces/curve/ICurveRouter.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/Path.sol";
import "../../utils/UniV3Actions.sol";

// cvxCRV single staking
contract StrategyConvexCRV is StratFeeManagerInitializable {
    using Path for bytes;
    using SafeERC20 for IERC20;

    // Tokens used
    address public constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant cvx = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant native = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant curveRouter = 0x99a58482BD75cbab83b27EC03CA68fF489b5788f;
    address public constant crvPool = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    address public constant cvxPool = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;
    IStakedCvxCrv public constant stakedCvxCrv = IStakedCvxCrv(0xaa0C3f5F7DFD688C6E646F66CD2a6B66ACdbE434);

    // cvxCRV
    address public constant want = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;

    // swapped via curveRouter
    CurveRoute public nativeToCvxCRV;

    struct CurveRoute {
        address[9] route;
        uint256[3][4] swapParams;
        uint minAmount; // minimum amount to be swapped to native
    }
    CurveRoute[] public rewards;

    struct RewardV3 {
        address token;
        bytes toNativePath; // uniswap path
        uint minAmount; // minimum amount to be swapped to native
    }
    RewardV3[] public rewardsV3; // rewards swapped via unirouter

    uint public curveSwapMinAmount;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        CurveRoute calldata _nativeToCvxCrv,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        nativeToCvxCRV = _nativeToCvxCrv;

        curveSwapMinAmount = 1e19;
        withdrawalFee = 1;
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            stakedCvxCrv.stake(wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            stakedCvxCrv.withdraw(_amount - wantBal);
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
        stakedCvxCrv.getReward(address(this));
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
        if (curveSwapMinAmount > 0) {
            uint bal = IERC20(crv).balanceOf(address(this));
            if (bal > curveSwapMinAmount) {
                ICurveSwap(crvPool).exchange(1, 0, bal, 0);
            }
            bal = IERC20(cvx).balanceOf(address(this));
            if (bal > curveSwapMinAmount) {
                ICurveSwap(cvxPool).exchange(1, 0, bal, 0);
            }
        }
        for (uint i; i < rewards.length; ++i) {
            uint bal = IERC20(rewards[i].route[0]).balanceOf(address(this));
            if (bal >= rewards[i].minAmount) {
                ICurveRouter(curveRouter).exchange_multiple(rewards[i].route, rewards[i].swapParams, bal, 0);
            }
        }
        for (uint i; i < rewardsV3.length; ++i) {
            uint bal = IERC20(rewardsV3[i].token).balanceOf(address(this));
            if (bal >= rewardsV3[i].minAmount) {
                UniV3Actions.swapV3WithDeadline(unirouter, rewardsV3[i].toNativePath, bal);
            }
        }
        uint256 nativeBal = address(this).balance;
        if (nativeBal > 0) {
            IWrappedNative(native).deposit{value : nativeBal}();
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
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        ICurveRouter(curveRouter).exchange_multiple(nativeToCvxCRV.route, nativeToCvxCRV.swapParams, nativeBal, 0);
    }

    function setNativeToWantRoute(address[9] calldata _route, uint[3][4] calldata _swapParams) external onlyOwner {
        require(_route[0] == native, "!native");
        nativeToCvxCRV = CurveRoute(_route, _swapParams, 0);
    }

    function addReward(address[9] calldata _rewardToNativeRoute, uint[3][4] calldata _swapParams, uint _minAmount) external onlyOwner {
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");
        require(token != address(stakedCvxCrv), "!staked");

        rewards.push(CurveRoute(_rewardToNativeRoute, _swapParams, _minAmount));
        IERC20(token).approve(curveRouter, 0);
        IERC20(token).approve(curveRouter, type(uint).max);
    }

    function addRewardV3(bytes memory _rewardToNativePath, uint _minAmount) external onlyOwner {
        address[] memory _rewardToNativeRoute = pathToRoute(_rewardToNativePath);
        address token = _rewardToNativeRoute[0];
        require(token != want, "!want");
        require(token != native, "!native");
        require(token != address(stakedCvxCrv), "!staked");

        rewardsV3.push(RewardV3(token, _rewardToNativePath, _minAmount));
        IERC20(token).approve(unirouter, 0);
        IERC20(token).approve(unirouter, type(uint).max);
    }

    function resetRewards() external onlyManager {
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
        return stakedCvxCrv.balanceOf(address(this));
    }

    function curveRouteToRoute(address[9] memory _route) public pure returns (address[] memory) {
        uint len;
        for (; len < _route.length; len++) {
            if (_route[len] == address(0)) break;
        }
        address[] memory route = new address[](len);
        for (uint i; i < len; i++) {
            route[i] = _route[i];
        }
        return route;
    }

    function nativeToWant() external view returns (address[] memory) {
        return curveRouteToRoute(nativeToCvxCRV.route);
    }

    function nativeToWantParams() external view returns (uint[3][4] memory) {
        return nativeToCvxCRV.swapParams;
    }

    function rewardToNative() external view returns (address[] memory) {
        return curveRouteToRoute(rewards[0].route);
    }

    function rewardToNative(uint i) external view returns (address[] memory) {
        return curveRouteToRoute(rewards[i].route);
    }

    function rewardToNativeParams(uint i) external view returns (uint[3][4] memory) {
        return rewards[i].swapParams;
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
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

    function rewardV3ToNative() external view returns (address[] memory) {
        return pathToRoute(rewardsV3[0].toNativePath);
    }

    function rewardV3ToNative(uint i) external view returns (address[] memory) {
        return pathToRoute(rewardsV3[i].toNativePath);
    }

    function rewardsV3Length() external view returns (uint) {
        return rewardsV3.length;
    }

    function rewardWeight() external view returns (uint) {
        return stakedCvxCrv.userRewardWeight(address(this));
    }

    function setRewardWeight(uint _weight) external onlyManager {
        stakedCvxCrv.setRewardWeight(_weight);
    }

    function setCurveSwapMinAmount(uint _minAmount) external onlyManager {
        curveSwapMinAmount = _minAmount;
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

        stakedCvxCrv.withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        stakedCvxCrv.withdraw(balanceOfPool());
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
        IERC20(want).approve(address(stakedCvxCrv), type(uint).max);
        IERC20(native).approve(curveRouter, type(uint).max);
        IERC20(crv).approve(crvPool, type(uint).max);
        IERC20(cvx).approve(cvxPool, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).approve(address(stakedCvxCrv), 0);
        IERC20(native).approve(curveRouter, 0);
        IERC20(crv).approve(crvPool, 0);
        IERC20(cvx).approve(cvxPool, 0);
    }

    receive() external payable {}
}
