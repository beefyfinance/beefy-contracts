// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/utils/math/Math.sol";
import "../../utils/UniswapV3Utils.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";
import "./IMellow.sol";

contract StrategyMellowVelo is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    address public veloRouter;
    address public lpToken0;
    address public lpToken1;
    bytes public outputToLp0Path;
    bytes public outputToLp1Path;

    function initialize(
        address _veloRouter,
        bytes calldata _outputToLp0Path,
        bytes calldata _outputToLp1Path,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);
        setHarvestOnDeposit(true);

        veloRouter = _veloRouter;
        outputToLp0Path = _outputToLp0Path;
        outputToLp1Path = _outputToLp1Path;
        lpToken0 = IMellowLpWrapper(want).token0();
        lpToken1 = IMellowLpWrapper(want).token1();
    }

    function stratName() public pure override returns (string memory) {
        return "MellowVelo";
    }

    function balanceOfPool() public pure override returns (uint) {
        return 0;
    }

    function _deposit(uint amount) internal override {}

    function _withdraw(uint amount) internal override {}

    function _emergencyWithdraw() internal override {}

    function _claim() internal override {
        IMellowLpWrapper(want).getRewards(address(this));
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        address output = depositToken == address(0) ? native : depositToken;
        if (output != native) {
            _swap(native, output);
        }

        IMellowLpWrapper lp = IMellowLpWrapper(want);
        uint totalSupply = lp.totalSupply();
        _swapToLpTokens(output, totalSupply);

        uint lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        (uint total0, uint total1) = lp.previewMint(totalSupply);
        uint lpAmount = Math.min(
            lp0Bal == 0 ? type(uint).max : totalSupply * lp0Bal / total0,
            lp1Bal == 0 ? type(uint).max : totalSupply * lp1Bal / total1
        );

        (uint actual0, uint actual1) = lp.previewMint(lpAmount);
        if (lp0Bal < actual0 || lp1Bal < actual1) {
            lpAmount--;
        }

        IERC20(lpToken0).forceApprove(want, lp0Bal);
        IERC20(lpToken1).forceApprove(want, lp1Bal);
        lp.mint(IMellowLpWrapper.MintParams(lpAmount, lp0Bal, lp1Bal, address(this), type(uint).max));
    }

    function _swapToLpTokens(address output, uint totalSupply) internal {
        IMellowLpWrapper lp = IMellowLpWrapper(want);
        (uint amount0, uint amount1) = lp.previewMint(totalSupply);
        (uint160 sqrtPriceX96,,,,,) = ICLPool(lp.pool()).slot0();
        uint price = (uint(sqrtPriceX96) * 1e18 / (2 ** 96)) ** 2;
        uint amount0inLp1 = amount0 * price / 1e36;
        uint outputBal = IERC20(output).balanceOf(address(this));
        uint toLp0 = outputBal * amount0inLp1 / (amount0inLp1 + amount1);
        uint toLp1 = outputBal - toLp0;

        _swap(output, lpToken0, outputToLp0Path, toLp0);
        _swap(output, lpToken1, outputToLp1Path, toLp1);
    }

    function _swap(address from, address to, bytes memory path, uint amount) internal {
        if (amount > 0 && from != to) {
            (address router,) = ISimplifiedSwapInfo(swapper).swapInfo(from, to);
            if (router != address(0)) {
                _swap(from, to, amount);
            } else {
                IERC20(from).forceApprove(veloRouter, amount);
                UniswapV3Utils.swap(veloRouter, path, amount);
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