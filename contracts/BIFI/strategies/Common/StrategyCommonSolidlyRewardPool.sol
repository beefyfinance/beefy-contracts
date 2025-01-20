// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "./BaseAllToNativeFactoryStrat.sol";

contract StrategyCommonSolidlyRewardPool is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IRewardPool public rewardPool;
    address public unirouter;

    bool public stable;
    address public lpToken0;
    address public lpToken1;

    // output is super.depositToken, output[0] must match depositToken
    ISolidlyRouter.Routes[] public outputToLp0Route;
    ISolidlyRouter.Routes[] public outputToLp1Route;

    function initialize(
        address _rewardPool,
        address _unirouter,
        ISolidlyRouter.Routes[] calldata _outputToLp0Route,
        ISolidlyRouter.Routes[] calldata _outputToLp1Route,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);

        rewardPool = IRewardPool(_rewardPool);
        unirouter = _unirouter;

        stable = ISolidlyPair(want).stable();
        lpToken0 = ISolidlyPair(want).token0();
        lpToken1 = ISolidlyPair(want).token1();

        for (uint i; i < _outputToLp0Route.length; ++i) {
            outputToLp0Route.push(_outputToLp0Route[i]);
        }
        for (uint i; i < _outputToLp1Route.length; ++i) {
            outputToLp1Route.push(_outputToLp1Route[i]);
        }

        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "CommonSolidlyRewardPool";
    }

    function balanceOfPool() public view override returns (uint) {
        return rewardPool.balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(rewardPool), amount);
        rewardPool.deposit(amount);
    }

    function _withdraw(uint amount) internal override {
        rewardPool.withdraw(amount);
    }

    function _emergencyWithdraw() internal override {
        uint amount = balanceOfPool();
        if (amount > 0) {
            if (rewardPool.emergency()) rewardPool.emergencyWithdraw();
            else rewardPool.withdraw(amount);
        }
    }

    function _claim() internal override {
        rewardPool.getReward();
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        address output = depositToken == address(0) ? native : depositToken;
        if (output != native) {
            _swap(native, output);
        }

        uint outputBal = IERC20(output).balanceOf(address(this));
        uint lp0Amt = outputBal / 2;
        uint lp1Amt = outputBal - lp0Amt;

        if (stable) {
            uint out0 = lp0Amt;
            if (lpToken0 != output) {
                out0 = ISolidlyRouter(unirouter).getAmountsOut(lp0Amt, outputToLp0Route)[outputToLp0Route.length];
            }
            uint out1 = lp1Amt;
            if (lpToken1 != output) {
                out1 = ISolidlyRouter(unirouter).getAmountsOut(lp1Amt, outputToLp1Route)[outputToLp1Route.length];
            }
            (uint amountA, uint amountB,) = ISolidlyRouter(unirouter).quoteAddLiquidity(lpToken0, lpToken1, stable, out0, out1);
            uint ratio = out0 * 1e18 / out1 * amountB / amountA;
            lp0Amt = outputBal * 1e18 / (ratio + 1e18);
            lp1Amt = outputBal - lp0Amt;
        }

        if (lpToken0 != output) {
            (address router,) = ISimplifiedSwapInfo(swapper).swapInfo(output, lpToken0);
            if (router != address(0)) {
                _swap(output, lpToken0, lp0Amt);
            } else {
                IERC20(output).forceApprove(unirouter, lp0Amt);
                ISolidlyRouter(unirouter).swapExactTokensForTokens(lp0Amt, 0, outputToLp0Route, address(this), block.timestamp);
            }
        }

        if (lpToken1 != output) {
            (address router,) = ISimplifiedSwapInfo(swapper).swapInfo(output, lpToken1);
            if (router != address(0)) {
                _swap(output, lpToken1, lp1Amt);
            } else {
                IERC20(output).forceApprove(unirouter, lp1Amt);
                ISolidlyRouter(unirouter).swapExactTokensForTokens(lp1Amt, 0, outputToLp1Route, address(this), block.timestamp);
            }
        }

        uint lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IERC20(lpToken0).forceApprove(unirouter, lp0Bal);
        IERC20(lpToken1).forceApprove(unirouter, lp1Bal);
        ISolidlyRouter(unirouter).addLiquidity(lpToken0, lpToken1, stable, lp0Bal, lp1Bal, 1, 1, address(this), block.timestamp);
    }

    function _solidlyToRoute(ISolidlyRouter.Routes[] memory _route) internal pure returns (address[] memory) {
        address[] memory route = new address[](_route.length + 1);
        route[0] = _route[0].from;
        for (uint i; i < _route.length; ++i) {
            route[i + 1] = _route[i].to;
        }
        return route;
    }

    function outputToLp0() external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = outputToLp0Route;
        return _solidlyToRoute(_route);
    }

    function outputToLp1() external view returns (address[] memory) {
        ISolidlyRouter.Routes[] memory _route = outputToLp1Route;
        return _solidlyToRoute(_route);
    }

    function setOutputToLp0Route(ISolidlyRouter.Routes[] calldata _outputToLp0) external onlyManager {
        require(_outputToLp0[0].from == depositToken, "!depositToken");
        delete outputToLp0Route;
        for (uint i; i < _outputToLp0.length; ++i) {
            outputToLp0Route.push(_outputToLp0[i]);
        }
    }

    function setOutputToLp1Route(ISolidlyRouter.Routes[] calldata _outputToLp1) external onlyManager {
        require(_outputToLp1[0].from == depositToken, "!depositToken");
        delete outputToLp1Route;
        for (uint i; i < _outputToLp1.length; ++i) {
            outputToLp1Route.push(_outputToLp1[i]);
        }
    }
}