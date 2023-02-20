// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/ISolidlyGauge.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/UniV3Actions.sol";

contract StrategyCommonSolidlyGaugeMultiRewardLP is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public gauge;
    address public uniV3Router;

    bool public stable;
    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    bool public shouldSweep;
    
    ISolidlyRouter.Routes[] public outputToNativeRoute;
    ISolidlyRouter.Routes[] public nativeToLp0Route;
    ISolidlyRouter.Routes[] public nativeToLp1Route;
    address[] public rewards;

    struct Reward {
         ISolidlyRouter.Routes[] rewardToNativeRoute;
         bytes routeToNative; // If swapping via UniV3;
         bool useUniV3;
    }

    mapping (address => Reward) public extraRewards;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _gauge,
        CommonAddresses calldata _commonAddresses,
        ISolidlyRouter.Routes[] calldata _outputToNativeRoute,
        ISolidlyRouter.Routes[] calldata _nativeToLp0Route,
        ISolidlyRouter.Routes[] calldata _nativeToLp1Route
    )  public initializer  {
         __StratFeeManager_init(_commonAddresses);
        want = _want;
        gauge = _gauge;
        uniV3Router = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);

        stable = ISolidlyPair(want).stable();

        for (uint i; i < _outputToNativeRoute.length; ++i) {
            outputToNativeRoute.push(_outputToNativeRoute[i]);
        }

        for (uint i; i < _nativeToLp0Route.length; ++i) {
            nativeToLp0Route.push(_nativeToLp0Route[i]);
        }

        for (uint i; i < _nativeToLp1Route.length; ++i) {
            nativeToLp1Route.push(_nativeToLp1Route[i]);
        }

        output = outputToNativeRoute[0].from;
        native = outputToNativeRoute[outputToNativeRoute.length -1].to;
        lpToken0 = nativeToLp0Route[nativeToLp0Route.length - 1].to;
        lpToken1 = nativeToLp1Route[nativeToLp1Route.length - 1].to;

        uint len = ISolidlyGauge(gauge).rewardsListLength();
        address[] memory rewardOptIns = new address[](len);
        for (uint i; i < len; ++i) {
            rewardOptIns[i] = ISolidlyGauge(gauge).rewards(i);
        }
        ISolidlyGauge(gauge).optIn(rewardOptIns);
        shouldSweep = true;

        rewards.push(output);
        _giveAllowances();
    }

    function _rewardExists(address _reward) private view returns (bool exists) {
        for (uint i; i < rewards.length;) {
            if (rewards[i] == _reward) {
                exists = true;
            }
            unchecked { ++i; }
        }
    }

    function deposit() public whenNotPaused  {
        if (shouldSweep) {
            _deposit();
        }
    }

    // puts the funds to work
    function _deposit() internal whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            ISolidlyGauge(gauge).deposit(wantBal, 0);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ISolidlyGauge(gauge).withdraw(_amount - wantBal);
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

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        ISolidlyGauge(gauge).getReward(address(this), rewards);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            _deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 toNative = IERC20(output).balanceOf(address(this));
        ISolidlyRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), block.timestamp);

        if (rewards.length > 1) {
            swapRewards();
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
    
    function swapRewards() internal {
        for (uint i; i < rewards.length; ++i) {
            if (rewards[i] != output) {
                uint256 bal = IERC20(rewards[i]).balanceOf(address(this));
                    if (bal > 0) {
                        if (!extraRewards[rewards[i]].useUniV3) {
                        ISolidlyRouter(unirouter).swapExactTokensForTokens(bal, 0, extraRewards[rewards[i]].rewardToNativeRoute, address(this), block.timestamp);
                    } else {
                        UniV3Actions.swapV3WithDeadline(uniV3Router, extraRewards[rewards[i]].routeToNative, bal);
                    }
                }
            }
        }
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        uint256 lp0Amt = nativeBal / 2;
        uint256 lp1Amt = nativeBal - lp0Amt;

        if (stable) {
            uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
            uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
            uint256 out0 = lpToken0 != native
                ? ISolidlyRouter(unirouter).getAmountsOut(lp0Amt, nativeToLp0Route)[nativeToLp0Route.length] * 1e18 / lp0Decimals
                : lp0Amt;
            uint256 out1 = lpToken1 != native 
                ? ISolidlyRouter(unirouter).getAmountsOut(lp1Amt, nativeToLp1Route)[nativeToLp1Route.length] * 1e18 / lp1Decimals
                : lp1Amt;
            (uint256 amountA, uint256 amountB,) = ISolidlyRouter(unirouter).quoteAddLiquidity(lpToken0, lpToken1, stable, out0, out1);
            amountA = amountA * 1e18 / lp0Decimals;
            amountB = amountB * 1e18 / lp1Decimals;
            uint256 ratio = out0 * 1e18 / out1 * amountB / amountA;
            lp0Amt = nativeBal * 1e18 / (ratio + 1e18);
            lp1Amt = nativeBal - lp0Amt;
        }

        if (lpToken0 != native) {
            ISolidlyRouter(unirouter).swapExactTokensForTokens(lp0Amt, 0, nativeToLp0Route, address(this), block.timestamp);
        }

        if (lpToken1 != native) {
            ISolidlyRouter(unirouter).swapExactTokensForTokens(lp1Amt, 0, nativeToLp1Route, address(this), block.timestamp);
        }

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        ISolidlyRouter(unirouter).addLiquidity(lpToken0, lpToken1, stable, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
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
        return ISolidlyGauge(gauge).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256) {
        return ISolidlyGauge(gauge).earned(output, address(this));
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            (nativeOut,) = ISolidlyRouter(unirouter).getAmountOut(outputBal, output, native);
            }

        return nativeOut * fees.total / DIVISOR * fees.call / DIVISOR;
    }


     function setShouldSweep(bool _shouldSweep) external onlyManager {
        shouldSweep = _shouldSweep;
    }

    function sweep() external {
        _deposit();
    }

    function deleteRewards() external onlyManager {
        for (uint i; i < rewards.length; ++i) {
            if (rewards[i] != output) {
                delete extraRewards[rewards[i]];
            }
        }
        delete rewards;
        rewards.push(output);
    }

    function addRewardToken(address _token, ISolidlyRouter.Routes[] calldata _route,  bytes calldata _routeToNative) external onlyOwner {
        require (!_rewardExists(_token), "Reward Exists");
        require (_token != address(want), "Reward Token");
        require (_token != address(output), "Output");

        bool optedIn = ISolidlyGauge(gauge).isOptIn(address(this), _token);
        if (!optedIn) {
            address[] memory tokens = new address[](1);
            tokens[0] = _token;
            ISolidlyGauge(gauge).optIn(tokens);
        }

        if (_route[0].from != address(0)) {
            IERC20(_token).safeApprove(unirouter, 0);
            IERC20(_token).safeApprove(unirouter, type(uint).max);
        } else {
            IERC20(_token).safeApprove(uniV3Router, 0);
            IERC20(_token).safeApprove(uniV3Router, type(uint).max);
        }

        rewards.push(_token);
            

        for (uint i; i < _route.length; ++i) {
            extraRewards[_token].rewardToNativeRoute.push(_route[i]);
        }

        extraRewards[_token].routeToNative = _routeToNative;
        extraRewards[_token].useUniV3 = _route[0].from == address(0) ? true : false;
    }

    function emergencyOptOut(address[] memory _tokens) external onlyManager {
        ISolidlyGauge(gauge).emergencyOptOut(_tokens);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        ISolidlyGauge(gauge).withdraw(balanceOfPool());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ISolidlyGauge(gauge).withdraw(balanceOfPool());
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();

        _deposit();
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(gauge, type(uint).max);
        for (uint i; i < rewards.length; ++i) {
            extraRewards[rewards[i]].useUniV3 
                ? IERC20(rewards[i]).safeApprove(uniV3Router, type(uint).max)
                : IERC20(rewards[i]).safeApprove(unirouter, type(uint).max);
        }

        IERC20(native).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(unirouter, type(uint).max);

        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, type(uint).max);

        IERC20(lpToken1).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(gauge, 0);
         for (uint i; i < rewards.length; ++i) {
            extraRewards[rewards[i]].useUniV3 
                ? IERC20(rewards[i]).safeApprove(uniV3Router, 0)
                : IERC20(rewards[i]).safeApprove(unirouter, 0);
        }

        IERC20(native).safeApprove(unirouter, 0);
        IERC20(lpToken0).safeApprove(unirouter, 0);
        IERC20(lpToken1).safeApprove(unirouter, 0);
    }

    function _solidlyToRoute(ISolidlyRouter.Routes[] memory _route) internal pure returns (address[] memory) {
        address[] memory route = new address[](_route.length + 1);
        route[0] = _route[0].from;
        for (uint i; i < _route.length; ++i) {
            route[i + 1] = _route[i].to;
        }
        return route;
    }

    function outputToNative() external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = outputToNativeRoute;
        return _solidlyToRoute(_route);
    }

    function nativeToLp0() external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = nativeToLp0Route;
        return _solidlyToRoute(_route);
    }

    function nativeToLp1() external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = nativeToLp1Route;
        return _solidlyToRoute(_route);
    }

    function rewardRoute(address _token) external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = extraRewards[_token].rewardToNativeRoute;
        return _solidlyToRoute(_route);
    }
}