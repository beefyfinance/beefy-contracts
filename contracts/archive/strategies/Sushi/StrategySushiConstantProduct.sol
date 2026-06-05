// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/sushi/ITridentRouter.sol";
import "../../interfaces/sushi/IBentoPool.sol";
import "../../interfaces/sushi/IBentoBox.sol";
import "../../interfaces/sushi/IMiniChefV2.sol";
import "../../interfaces/sushi/IRewarder.sol";
import "../Common/StratFeeManager.sol";
import "../../utils/GasFeeThrottler.sol";

contract StrategySushiConstantProduct is StratFeeManager, GasFeeThrottler {
    using SafeERC20 for IERC20;

    struct Routes {
        address[] outputToNative;
        address[] rewardToNative;
        address[] nativeToLp0;
        address[] nativeToLp1;
    }

    struct Pools {
        address[] outputToNative;
        address[] rewardToNative;
        address[] nativeToLp0Pool;
        address[] nativeToLp1Pool;
    }

    struct SwapParams {
        ITridentRouter.ExactInputParams outputToNative;
        ITridentRouter.ExactInputParams rewardToNative;
        ITridentRouter.ExactInputParams nativeToLp0;
        ITridentRouter.ExactInputParams nativeToLp1;
    }

    // Tokens used
    address public native;
    address public output;
    address public reward;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public chef;
    uint256 public poolId;
    address public bentoBox;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    // Routes
    Routes private routes;
    Pools private pools;
    SwapParams private params;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _bentoBox,
        Routes memory _routes,
        Pools memory _pools,
        CommonAddresses memory _commonAddresses
    ) StratFeeManager(_commonAddresses) {
        want = _want;
        poolId = _poolId;
        chef = _chef;
        bentoBox = _bentoBox;
        routes = _routes;
        pools = _pools;

        output = _routes.outputToNative[0];
        native = _routes.outputToNative[_routes.outputToNative.length - 1];
        assignParams(_routes.outputToNative, _pools.outputToNative, params.outputToNative);

        require(_routes.rewardToNative[_routes.rewardToNative.length - 1] == native, "rewardToNative[last] != native");
        reward = _routes.rewardToNative[0];
        assignParams(_routes.rewardToNative, _pools.rewardToNative, params.rewardToNative);

        // setup lp routing
        lpToken0 = IBentoPool(want).token0();
        require(_routes.nativeToLp0[0] == native, "nativeToLp0[0] != native");
        require(_routes.nativeToLp0[_routes.nativeToLp0.length - 1] == lpToken0, "nativeToLp0[last] != lpToken0");
        assignParams(_routes.nativeToLp0, _pools.nativeToLp0Pool, params.nativeToLp0);

        lpToken1 = IBentoPool(want).token1();
        require(_routes.nativeToLp1[0] == native, "nativeToLp1[0] != native");
        require(_routes.nativeToLp1[_routes.nativeToLp1.length - 1] == lpToken1, "nativeToLp1[last] != lpToken1");
        assignParams(_routes.nativeToLp1, _pools.nativeToLp1Pool, params.nativeToLp1);

        IBentoBox(bentoBox).setMasterContractApproval(address(this), unirouter, true, 0, bytes32(0), bytes32(0));

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMiniChefV2(chef).deposit(poolId, wantBal, address(this));
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMiniChefV2(chef).withdraw(poolId, _amount - wantBal, address(this));
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
            _harvest(tx.origin);
        }
    }

    function harvest() external gasThrottle virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external gasThrottle virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IMiniChefV2(chef).harvest(poolId, address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        uint256 rewardBal = IERC20(reward).balanceOf(address(this));
        if (outputBal > 0 || rewardBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();

        uint256 rewardBal = IERC20(reward).balanceOf(address(this));
        if (rewardBal > 0 && reward != native) {
            ITridentRouter.ExactInputParams memory _rewardToNative = params.rewardToNative;
            _rewardToNative.amountIn = rewardBal;
            ITridentRouter(unirouter).exactInputWithNativeToken(_rewardToNative);
        }

        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            ITridentRouter.ExactInputParams memory _outputToNative = params.outputToNative;
            _outputToNative.amountIn = outputBal;
            ITridentRouter(unirouter).exactInputWithNativeToken(_outputToNative);
        }

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
        uint256 nativeHalf = IERC20(native).balanceOf(address(this)) / 2;

        if (lpToken0 != native) {
            ITridentRouter.ExactInputParams memory _nativeToLp0 = params.nativeToLp0;
            _nativeToLp0.amountIn = nativeHalf;
            ITridentRouter(unirouter).exactInputWithNativeToken(_nativeToLp0);
        }

        if (lpToken1 != native) {
            ITridentRouter.ExactInputParams memory _nativeToLp1 = params.nativeToLp1;
            _nativeToLp1.amountIn = nativeHalf;
            ITridentRouter(unirouter).exactInputWithNativeToken(_nativeToLp1);
        }

        ITridentRouter.TokenInput[] memory tokens = new ITridentRouter.TokenInput[](2);
        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        tokens[0] = ITridentRouter.TokenInput(lpToken0, true, lp0Bal);
        tokens[1] = ITridentRouter.TokenInput(lpToken1, true, lp1Bal);
        bytes memory data = abi.encode(address(this));

        ITridentRouter(unirouter).addLiquidity(tokens, want, 1, data);
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
        (uint256 _amount, ) = IMiniChefV2(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return IMiniChefV2(chef).pendingSushi(poolId, address(this));
    }

    // native reward amount for calling harvest
    function callReward() external view returns (uint256) {
        uint256 pendingReward;
        address rewarder = IMiniChefV2(chef).rewarder(poolId);
        if (rewarder != address(0)) {
            pendingReward = IRewarder(rewarder).pendingToken(poolId, address(this));
        }

        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;

        if (reward == native) {
            nativeOut = pendingReward;
        } else if (pendingReward > 0) {
            uint256 poolLength = params.rewardToNative.path.length;
            uint256 amount = pendingReward;
            for (uint i; i < poolLength;) {
                bytes memory data = abi.encode(routes.rewardToNative[i], amount);
                amount = IBentoPool(params.rewardToNative.path[i].pool).getAmountOut(data);
                unchecked { ++i; }
            }
            nativeOut = amount;
        }

        if (outputBal > 0) {
            bytes memory data = abi.encode(output, outputBal);
            nativeOut += IBentoPool(params.outputToNative.path[0].pool).getAmountOut(data);
        }

        IFeeConfig.FeeCategory memory fees = getFees();
        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMiniChefV2(chef).emergencyWithdraw(poolId, address(this));

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMiniChefV2(chef).emergencyWithdraw(poolId, address(this));
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
        IERC20(want).safeApprove(chef, type(uint).max);
        IERC20(output).safeApprove(bentoBox, type(uint).max);
        IERC20(native).safeApprove(bentoBox, type(uint).max);

        IERC20(lpToken0).safeApprove(bentoBox, 0);
        IERC20(lpToken0).safeApprove(bentoBox, type(uint).max);

        IERC20(lpToken1).safeApprove(bentoBox, 0);
        IERC20(lpToken1).safeApprove(bentoBox, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(bentoBox, 0);
        IERC20(native).safeApprove(bentoBox, 0);
        IERC20(lpToken0).safeApprove(bentoBox, 0);
        IERC20(lpToken1).safeApprove(bentoBox, 0);
    }

    function outputToNative() external view returns (address[] memory) {
        return routes.outputToNative;
    }

    function rewardToNative() external view returns (address[] memory) {
        return routes.rewardToNative;
    }

    function nativeToLp0() external view returns (address[] memory) {
        return routes.nativeToLp0;
    }

    function nativeToLp1() external view returns (address[] memory) {
        return routes.nativeToLp1;
    }

    function assignParams(address[] memory _route, address[] memory _pools, ITridentRouter.ExactInputParams storage _params) internal {
        uint256 routeLength = _route.length;
        uint256 poolLength = _pools.length;
        if (routeLength == 1) {
            return;
        }
        require (_route.length == poolLength + 1, "mismatch route pool length");
        
        bool unwrapBento;
        address destination;
        for (uint i; i < poolLength;) {
            if (i == poolLength - 1) {
                unwrapBento = true;
                destination = address(this);
            } else {
                destination = _pools[i+1];
            }
            _params.path.push(ITridentRouter.Path(_pools[i], abi.encode(_route[i], destination, unwrapBento)));
            unchecked { ++i; }
        }

        _params.tokenIn = _route[0];
        _params.amountOutMinimum = 1;
    }
}
