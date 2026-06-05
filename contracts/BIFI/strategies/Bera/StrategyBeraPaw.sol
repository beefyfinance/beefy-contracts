// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../utils/UniV3Actions.sol";
import "../../utils/UniswapV3Utils.sol";
import "../../interfaces/beethovenx/IBalancerPool.sol";
import "../../interfaces/beethovenx/IBalancerVault.sol";
import {BalancerActionsLib} from "../Balancer/BalancerActionsLib.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";
import "./IKodiak.sol";
import "./IRewardVault.sol";
import "./IBGT.sol";
import "./IBeraPaw.sol";

contract StrategyBeraPaw is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    address public constant kodiakRouter = 0xe301E48F77963D3F7DbD2a4796962Bd7f3867Fb4;
    address public constant beraPawForge = 0xFeedb9750d6ac77D2E52e0C9EB8fB79F9de5Cafe;
    IBGT public constant BGT = IBGT(0x656b95E550C07a9ffe548bd4085c72418Ceb1dba);

    IRewardVault public gauge;
    address public lpToken0;
    address public lpToken1;

    address public balancerVault;
    bytes32 public balancerPoolId;

    IUniV3Pool public pool;

    bool public isKodiak;
    bytes public outputToLp0Path;
    bytes public outputToLp1Path;

    function initialize(
        address _gauge,
        bool _isKodiak,
        bytes calldata _outputToLp0Path,
        bytes calldata _outputToLp1Path,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);

        gauge = IRewardVault(_gauge);
        isKodiak = _isKodiak;
        outputToLp0Path = _outputToLp0Path;
        outputToLp1Path = _outputToLp1Path;
        if (_isKodiak) {
            pool = IUniV3Pool(IKodiakIsland(want).pool());
            lpToken0 = pool.token0();
            lpToken1 = pool.token1();
        } else {
            balancerVault = IBalancerPool(want).getVault();
            balancerPoolId = IBalancerPool(want).getPoolId();
            (address[] memory lpTokens,,) = IBalancerVault(balancerVault).getPoolTokens(balancerPoolId);
            lpToken0 = lpTokens[0];
            lpToken1 = lpTokens[1];
        }
        gauge.setOperator(beraPawForge);
        setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "BeraPaw";
    }

    function balanceOfPool() public view override returns (uint) {
        return gauge.balanceOf(address(this)) - gauge.getTotalDelegateStaked(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(gauge), amount);
        gauge.stake(amount);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            gauge.withdraw(amount);
        }
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        if (gauge.earned(address(this)) > 0) {
            IBeraPaw(beraPawForge).mint(address(this), address(gauge), address(this));
        }
        uint bgtBal = BGT.balanceOf(address(this));
        if (bgtBal > 0) {
            BGT.redeem(address(this), bgtBal);
            IWrappedNative(native).deposit{value: address(this).balance}();
        }
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        address output = depositToken == address(0) ? native : depositToken;
        if (output != native) {
            _swap(native, output);
        }

        if (isKodiak) {
            _buildKodiakLp(output);
        } else {
            _buildBalancerLp(output);
        }
    }

    function _buildBalancerLp(address depositToken) internal {
        uint256 bal = IERC20(depositToken).balanceOf(address(this));
        IERC20(depositToken).forceApprove(balancerVault, bal);
        BalancerActionsLib.balancerJoin(balancerVault, balancerPoolId, depositToken, bal);
    }

    function _buildKodiakLp(address output) internal {
        (uint amount0, uint amount1) = IKodiakIsland(want).getUnderlyingBalances();
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        uint price = (uint(sqrtPriceX96) * 1e18 / (2 ** 96)) ** 2;
        uint amount0inLp1 = amount0 * price / 1e36;
        uint outputBal = IERC20(output).balanceOf(address(this));
        uint toLp0 = outputBal * amount0inLp1 / (amount0inLp1 + amount1);
        uint toLp1 = outputBal - toLp0;

        _swap(output, lpToken0, outputToLp0Path, toLp0);
        _swap(output, lpToken1, outputToLp1Path, toLp1);

        uint lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IERC20(lpToken0).forceApprove(want, lp0Bal);
        IERC20(lpToken1).forceApprove(want, lp1Bal);
        (,, uint mintAmount) = IKodiakIsland(want).getMintAmounts(lp0Bal, lp1Bal);
        IKodiakIsland(want).mint(mintAmount, address(this));
    }

    function _swap(address from, address to, bytes memory path, uint amount) internal {
        if (amount > 0 && from != to) {
            (address router,) = ISimplifiedSwapInfo(swapper).swapInfo(from, to);
            if (router != address(0)) {
                _swap(from, to, amount);
            } else {
                IERC20(from).forceApprove(kodiakRouter, amount);
                UniV3Actions.swapV3(kodiakRouter, path, amount);
            }
        }
    }

    function setOutputToLp0(bytes calldata _outputToLp0Path) public onlyManager {
        if (_outputToLp0Path.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_outputToLp0Path);
            require(route[0] == depositToken, "!depositToken");
            require(route[route.length - 1] == lpToken0, "!lp0");
        }
        outputToLp0Path = _outputToLp0Path;
    }

    function setOutputToLp1(bytes calldata _outputToLp1Path) public onlyManager {
        if (_outputToLp1Path.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_outputToLp1Path);
            require(route[0] == depositToken, "!depositToken");
            require(route[route.length - 1] == lpToken1, "!lp1");
        }
        outputToLp1Path = _outputToLp1Path;
    }

    function outputToLp0() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(outputToLp0Path);
    }

    function outputToLp1() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(outputToLp1Path);
    }

}