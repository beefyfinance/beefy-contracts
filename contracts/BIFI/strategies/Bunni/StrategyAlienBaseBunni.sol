// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/common/IERC20Extended.sol";
import "../../interfaces/common/IMasterChef.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";
import "./IBunni.sol";
import "../../utils/TickMath.sol";
import "../../utils/LiquidityAmounts.sol";
import "../../utils/UniV3Actions.sol";
import "../../utils/UniswapV3Utils.sol";

contract StrategyAlienBaseBunni is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IMasterChef public constant chef = IMasterChef(0x52eaeCAC2402633d98b95213d0b473E069D86590);
    address public constant unirouter = 0xB20C411FC84FBB27e78608C24d0056D974ea9411;

    uint public pid;
    address public hub;
    IUniV3Pool public pool;
    address public lpToken0;
    address public lpToken1;
    uint public lp0Decimals;
    int24 public tickLower;
    int24 public tickUpper;

    bytes public outputToLp0Path;
    bytes public outputToLp1Path;

    function initialize(
        uint _pid,
        bool _harvestOnDeposit,
        bytes calldata _outputToLp0Path,
        bytes calldata _outputToLp1Path,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        __BaseStrategy_init(_addresses, _rewards);

        pid = _pid;
        outputToLp0Path = _outputToLp0Path;
        outputToLp1Path = _outputToLp1Path;

        hub = IBunniToken(want).hub();
        pool = IUniV3Pool(IBunniToken(want).pool());
        lpToken0 = pool.token0();
        lpToken1 = pool.token1();
        lp0Decimals = 10 ** IERC20Extended(lpToken0).decimals();
        tickLower = IBunniToken(want).tickLower();
        tickUpper = IBunniToken(want).tickUpper();

        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "AlienBaseBunni";
    }

    function balanceOfPool() public view override returns (uint) {
        (uint amount,) = chef.userInfo(pid, address(this));
        return amount;
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(chef), amount);
        chef.deposit(pid, amount);
    }

    function _withdraw(uint amount) internal override {
        chef.withdraw(pid, amount);
    }

    function _emergencyWithdraw() internal override {
        chef.emergencyWithdraw(pid);
    }

    function _claim() internal override {
        chef.deposit(pid, 0);
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        address output = depositToken == address(0) ? native : depositToken;
        if (output != native) {
            _swap(native, output);
        }

        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        uint price = (uint(sqrtPriceX96) * 1e18 / (2 ** 96)) ** 2 / 1e18 / (1e18 / lp0Decimals);
        uint in0 = lp0Decimals;
        uint in1 = price;

        (uint128 liquidity,,,,) = pool.positions(keccak256(abi.encodePacked(hub, tickLower, tickUpper)));
        (uint amount0, uint amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );

        uint ratio = in0 * 1e18 / in1 * amount1 / amount0;
        uint outputBal = IERC20(output).balanceOf(address(this));
        uint toLp0 = outputBal * 1e18 / (ratio + 1e18);
        uint toLp1 = outputBal - toLp0;

        _swapToLp(output, lpToken0, outputToLp0Path, toLp0);
        _swapToLp(output, lpToken1, outputToLp1Path, toLp1);

        uint lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        IBunniHub.BunniKey memory key = IBunniHub.BunniKey(address(pool), tickLower, tickUpper);
        IBunniHub.DepositParams memory params = IBunniHub.DepositParams(key, lp0Bal, lp1Bal, 0, 0, block.timestamp, address(this));
        IERC20(lpToken0).forceApprove(hub, lp0Bal);
        IERC20(lpToken1).forceApprove(hub, lp1Bal);
        IBunniHub(hub).deposit(params);
    }

    function _swapToLp(address from, address to, bytes memory path, uint amount) internal {
        if (from != to) {
            (address router,) = ISimplifiedSwapInfo(swapper).swapInfo(from, to);
            if (router != address(0)) {
                _swap(from, to, amount);
            } else {
                IERC20(from).forceApprove(unirouter, amount);
                UniV3Actions.swapV3(unirouter, path, amount);
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