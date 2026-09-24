// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

interface IMimLp {
    function _BASE_TOKEN_() external view returns (address);
    function _QUOTE_TOKEN_() external view returns (address);
    function getReserves() external view returns (uint baseReserve, uint quoteReserve);
}

interface IMimRouter {
    function addLiquidity(address lp, address to, uint baseInAmount, uint quoteInAmount, uint minimumShares, uint deadline)
    external returns (uint, uint, uint);
}

contract StrategyMimSwap is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IRewardPool public gauge;
    address public mimRouter;
    address public lpToken0;
    address public lpToken1;

    function initialize(
        IRewardPool _gauge,
        address _router,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer  {
        __BaseStrategy_init(_addresses, _rewards);
        lpToken0 = IMimLp(want)._BASE_TOKEN_();
        lpToken1 = IMimLp(want)._QUOTE_TOKEN_();
        gauge = _gauge;
        mimRouter = _router;
        setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "MimSwap";
    }

    function balanceOfPool() public view override returns (uint) {
        return gauge.balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(gauge), amount);
        gauge.stake(amount);
    }

    function _withdraw(uint amount) internal override {
        gauge.withdraw(amount);
    }

    function _emergencyWithdraw() internal override {
        uint amount = balanceOfPool();
        if (amount > 0) {
            gauge.withdraw(amount);
        }
    }

    function _claim() internal override {
        gauge.getRewards();
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        (uint toLp0, uint toLp1) = quoteAddLiquidity();

        if (lpToken0 != native) {
            _swap(native, lpToken0, toLp0);
        }
        if (lpToken1 != native) {
            _swap(native, lpToken1, toLp1);
        }

        uint lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IERC20(lpToken0).forceApprove(mimRouter, lp0Bal);
        IERC20(lpToken1).forceApprove(mimRouter, lp1Bal);
        IMimRouter(mimRouter).addLiquidity(want, address(this), lp0Bal, lp1Bal, 0, type(uint).max);
    }

    function quoteAddLiquidity() internal view returns (uint toLp0, uint toLp1) {
        uint decimals0 = 10 ** IERC20Extended(lpToken0).decimals();
        uint decimals1 = 10 ** IERC20Extended(lpToken1).decimals();
        (uint reserve0, uint reserve1) = IMimLp(want).getReserves();
        reserve0 = reserve0 * 1e18 / decimals0;
        reserve1 = reserve1 * 1e18 / decimals1;

        uint nativeBal = IERC20(native).balanceOf(address(this));
        toLp0 = nativeBal * reserve0 / (reserve0 + reserve1);
        toLp1 = nativeBal - toLp0;
    }
}