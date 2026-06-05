// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../../interfaces/common/IUniV3Quoter.sol";
import "../../utils/UniswapV3Utils.sol";
import "../Common/BaseAllToNativeFactoryStrat.sol";

interface IPearlLiquidBox {
    function getSqrtTwapX96(uint32 twapInterval) external view returns (uint160 sqrtPriceX96, uint160);
    function getRequiredAmountsForInput(uint amount0, uint amount1) external view returns (uint, uint);
    function boxFactory() external view returns (IPearlLiquidBoxFactory);
}

interface IPearlLiquidBoxFactory {
    function boxManager() external view returns (address);
}

interface IPearlLiquidBoxManager {
    function deposit(address box,uint deposit0,uint deposit1,uint amount0Min,uint amount1Min) external returns (uint shares);
}

contract StrategyPearlTrident is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    IUniV3Quoter public constant quoter = IUniV3Quoter(0xDe43aBe37aB3b5202c22422795A527151d65Eb18);
    address public constant unirouter = 0xa1F56f72b0320179b01A947A5F78678E8F96F8EC;

    IRewardPool public gauge;
    address public lpToken0;
    address public lpToken1;
    bytes public nativeToLp0Path;
    bytes public nativeToLp1Path;
    bool public isFastQuote;

    function initialize(
        IRewardPool _gauge,
        bytes calldata _nativeToLp0Path,
        bytes calldata _nativeToLp1Path,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer  {
        __BaseStrategy_init(_addresses, _rewards);
        gauge = _gauge;
        nativeToLp0Path = _nativeToLp0Path;
        nativeToLp1Path = _nativeToLp1Path;
        lpToken0 = ISolidlyPair(want).token0();
        lpToken1 = ISolidlyPair(want).token1();
        setHarvestOnDeposit(true);
        IERC20(native).approve(unirouter, type(uint).max);
    }

    function stratName() public pure override returns (string memory) {
        return "PearlTrident";
    }

    function balanceOfPool() public view override returns (uint) {
        return gauge.balanceOf(address(this));
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(gauge), amount);
        gauge.deposit(amount);
    }

    function _withdraw(uint amount) internal override {
        gauge.withdraw(amount);
    }

    function _emergencyWithdraw() internal override {
        uint amount = balanceOfPool();
        if (amount > 0) {
            if (gauge.emergency()) gauge.emergencyWithdraw();
            else gauge.withdraw(amount);
        }
    }

    function _claim() internal override {
        gauge.collectReward();
    }

    function _verifyRewardToken(address token) internal view override {}

    function _swapNativeToWant() internal override {
        (uint toLp0, uint toLp1) = quoteAddLiquidity();

        if (nativeToLp0Path.length > 0) {
            UniswapV3Utils.swap(unirouter, nativeToLp0Path, toLp0);
        }
        if (nativeToLp1Path.length > 0) {
            UniswapV3Utils.swap(unirouter, nativeToLp1Path, toLp1);
        }

        uint lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint lp1Bal = IERC20(lpToken1).balanceOf(address(this));
        address manager = boxManager();
        IERC20(lpToken0).forceApprove(manager, lp0Bal);
        IERC20(lpToken1).forceApprove(manager, lp1Bal);
        IPearlLiquidBoxManager(manager).deposit(want, lp0Bal, lp1Bal, 0, 0);
    }

    function quoteAddLiquidity() internal returns (uint toLp0, uint toLp1) {
        uint nativeBal = IERC20(native).balanceOf(address(this));
        uint in0;
        uint in1;

        if (isFastQuote) {
            uint lp0Decimals = 10 ** IERC20Extended(lpToken0).decimals();
            (uint sqrtPriceX96,) = IPearlLiquidBox(want).getSqrtTwapX96(0);
            uint price = sqrtPriceX96 ** 2 * 1e12 / (2 ** 192) * lp0Decimals / 1e12;
            in0 = lp0Decimals;
            in1 = price;
        } else {
            in0 = nativeBal / 2;
            in1 = nativeBal - in0;
            if (nativeToLp0Path.length > 0) {
                in0 = quoter.quoteExactInput(nativeToLp0Path, in0);
            }
            if (nativeToLp1Path.length > 0) {
                in1 = quoter.quoteExactInput(nativeToLp1Path, in1);
            }
        }

        (uint amount0, uint amount1) = IPearlLiquidBox(want).getRequiredAmountsForInput(in0, in1);
        uint ratio0 = amount0 * 1e18 / in0;
        uint ratio1 = amount1 * 1e18 / in1;
        if (ratio0 == 0) {
            toLp0 = 0;
            toLp1 = nativeBal;
        } else if (ratio1 == 0) {
            toLp0 = nativeBal;
            toLp1 = 0;
        } else if (ratio0 < ratio1) {
            toLp1 = nativeBal * 1e18 / (ratio0 + 1e18);
            toLp0 = nativeBal - toLp1;
        } else {
            toLp0 = nativeBal * 1e18 / (ratio1 + 1e18);
            toLp1 = nativeBal - toLp0;
        }
    }

    function setFastQuote(bool _isFastQuote) external onlyManager {
        isFastQuote = _isFastQuote;
    }

    function boxManager() public view returns (address) {
        return IPearlLiquidBox(want).boxFactory().boxManager();
    }

    function setNativeToLp0(bytes calldata _nativeToLp0Path) public onlyManager {
        if (_nativeToLp0Path.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_nativeToLp0Path);
            require(route[0] == native, "!native");
            require(route[route.length - 1] == lpToken0, "!lp0");
        }
        nativeToLp0Path = _nativeToLp0Path;
    }

    function setNativeToLp1(bytes calldata _nativeToLp1Path) public onlyManager {
        if (_nativeToLp1Path.length > 0) {
            address[] memory route = UniswapV3Utils.pathToRoute(_nativeToLp1Path);
            require(route[0] == native, "!native");
            require(route[route.length - 1] == lpToken1, "!lp1");
        }
        nativeToLp1Path = _nativeToLp1Path;
    }

    function nativeToLp0() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToLp0Path);
    }

    function nativeToLp1() external view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(nativeToLp1Path);
    }
}