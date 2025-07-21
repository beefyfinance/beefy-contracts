// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/common/ISolidlyRouter.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/GasFeeThrottler.sol";
import "../../utils/AlgebraUtils.sol";

interface IGammaUniProxy {
    function getDepositAmount(address pos, address token, uint _deposit) external view returns (uint amountStart, uint amountEnd);
    function deposit(uint deposit0, uint deposit1, address to, address pos, uint[4] memory minIn) external returns (uint shares);
}

interface IAlgebraPool {
    function pool() external view returns(address);
    function globalState() external view returns(uint);
}

interface IAlgebraQuoter {
    function quoteExactInput(bytes memory path, uint amountIn) external returns (uint amountOut, uint16[] memory fees);
}

interface IHypervisor {
    function whitelistedAddress() external view returns (address uniProxy);
}

interface IFlashPool {
    function swap(uint256 amount0, uint256 amount1, address to, bytes calldata data) external;
}

interface IOptionsToken {
    function exercise(uint256 amount, uint256 maxPaymentAmount, address to, uint256 deadline) external;
    function getDiscountedPrice(uint256 amount) external view returns (uint256);
}

interface IPairFactory {
    function stableFee() external view returns (uint256);
}

contract StrategyLynexSolidly is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public constant native = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;
    address public constant output = 0x1a51b19CE03dbE0Cb44C1528E34a7EDD7771E9Af;
    address public constant otoken = 0x63349BA5E1F71252eCD56E8F950D1A518B400b60;
    address public constant paymentToken = 0x176211869cA2b568f2A7D4EE941E073a821EE1ff;
    address public constant flashPool = 0xa4477d98e519D4c1d66aEf4EfDF7cBEb84f4f778;
    address public constant algebraRouter = 0x3921e8cb45B17fC029A0a6dE958330ca4e583390;
    address public constant pairFactory = 0xBc7695Fd00E3b32D08124b7a4287493aEE99f9ee;

    address public want;
    address public lpToken0;
    address public lpToken1;

    // Third party contracts
    address public rewardPool;
    IAlgebraQuoter public constant quoter = IAlgebraQuoter(0x851d97Fd7823E44193d227682e32234ef8CaC83e);

    bool public stable;
    bool public useNative;
    bool public harvestOnDeposit;
    bool private flashOn;
    bool private useSolidlyFor0;
    bool private useSolidlyFor1;
    uint256 public lastHarvest;
    
    ISolidlyRouter.Routes[] public nativeToLp0Route;
    ISolidlyRouter.Routes[] public nativeToLp1Route;
    bytes public outputToPaymentPath;
    bytes public paymentToNativePath;
    bytes public nativeToPayment;
    bytes public nativeToLp0Path;
    bytes public nativeToLp1Path;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _rewardPool,
        bool _useNative,
        bool[] calldata _useSolidly,
        ISolidlyRouter.Routes[] calldata _nativeToLp0Route,
        ISolidlyRouter.Routes[] calldata _nativeToLp1Route,
        bytes[] calldata _paths,
        CommonAddresses calldata _commonAddresses
     ) public initializer  {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        rewardPool = _rewardPool;

        useSolidlyFor0 = _useSolidly[0];
        useSolidlyFor1 = _useSolidly[1];
        useNative = _useNative;

        lpToken0 = ISolidlyPair(want).token0();
        lpToken1 = ISolidlyPair(want).token1();

        stable = ISolidlyPair(want).stable();

        if (!useSolidlyFor0) setNativeToLp0(_paths[0]);
        else {
            for (uint i; i < _nativeToLp0Route.length; ++i) {
                nativeToLp0Route.push(_nativeToLp0Route[i]);
            }
        }

        if (!useSolidlyFor1) setNativeToLp1(_paths[1]);
        else {
            for (uint i; i < _nativeToLp1Route.length; ++i) {
                nativeToLp1Route.push(_nativeToLp1Route[i]);
            }
        }

        address[] memory outputToPaymentRoute = new address[](2);
        outputToPaymentRoute[0] = output;
        outputToPaymentRoute[1] = paymentToken;

        address[] memory paymentToNativeRoute = new address[](2);
        paymentToNativeRoute[0] = paymentToken;
        paymentToNativeRoute[1] = native;

        address[] memory nativeToPaymentRoute = new address[](2);
        nativeToPaymentRoute[0] = native;
        nativeToPaymentRoute[1] = paymentToken;

        outputToPaymentPath = AlgebraUtils.routeToPath(outputToPaymentRoute);
        paymentToNativePath = AlgebraUtils.routeToPath(paymentToNativeRoute);
        nativeToPayment = AlgebraUtils.routeToPath(nativeToPaymentRoute);

        harvestOnDeposit = true;
        withdrawalFee = 0;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IRewardPool(rewardPool).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IRewardPool(rewardPool).withdraw(_amount - wantBal);
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
        IRewardPool(rewardPool).getReward();
        uint256 outputBal = IERC20(otoken).balanceOf(address(this));
        if (outputBal > 0) {
            flashExercise(outputBal);
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function hook(address sender, uint256 amount0, uint256, bytes memory) external {
        require(sender == address(this), "wrong sender");
        require(msg.sender == flashPool, "!flashPool");
        require(flashOn, "!flashOn");

        uint256 oTokenBal = IERC20(otoken).balanceOf(address(this));
        IOptionsToken(otoken).exercise(oTokenBal, amount0, address(this), block.timestamp);

        uint256 outputTokenBal = IERC20(output).balanceOf(address(this));
        AlgebraUtils.swap(algebraRouter, outputToPaymentPath, outputTokenBal);

        uint256 debt = amount0 + getTotalFlashFee(amount0);
        IERC20(paymentToken).safeTransfer(flashPool, debt);

        uint256 paymentTokenBal = IERC20(paymentToken).balanceOf(address(this));
        AlgebraUtils.swap(algebraRouter, paymentToNativePath, paymentTokenBal);
        flashOn = false;
    }

    function getTotalFlashFee(uint256 _paymentTokenNeeded) private view returns (uint256) {
        uint256 stableFee = IPairFactory(pairFactory).stableFee();
        return _paymentTokenNeeded * stableFee / (10000 - stableFee);
    }

    function flashExercise(uint256 _amount) internal {
        uint256 amountNeeded = IOptionsToken(otoken).getDiscountedPrice(_amount);
        flashOn = true;
        IFlashPool(flashPool).swap(amountNeeded, 0, address(this), "Beefy");
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
        if (!useNative) {    
            AlgebraUtils.swap(algebraRouter, nativeToPayment, nativeBal);
            nativeBal = IERC20(paymentToken).balanceOf(address(this));
        }

        uint256 lp0Amt = nativeBal / 2;
        uint256 lp1Amt = nativeBal - lp0Amt;

        address swapToken = useNative ? native : paymentToken;

        if (stable) {
            uint256 lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
            uint256 lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
            uint256 out0;
            uint256 out1;
             if (lpToken0 != swapToken) {
                if (useSolidlyFor0) out0 = ISolidlyRouter(unirouter).getAmountsOut(lp0Amt, nativeToLp0Route)[nativeToLp0Route.length];
                else (out0,) =  quoter.quoteExactInput(nativeToLp0Path, lp0Amt);
            } else out0 = lp0Amt;

            if (lpToken1 != swapToken) {
                if (useSolidlyFor1) out1 = ISolidlyRouter(unirouter).getAmountsOut(lp1Amt, nativeToLp1Route)[nativeToLp1Route.length];
                else (out1,) =  quoter.quoteExactInput(nativeToLp1Path, lp1Amt);
            } else out1 = lp1Amt;
            
            out0 =  out0 * 1e18 / lp0Decimals;
            out1 =  out1 * 1e18 / lp1Decimals;

            (uint256 amountA, uint256 amountB,) = ISolidlyRouter(unirouter).quoteAddLiquidity(lpToken0, lpToken1, stable, out0, out1);
            amountA = amountA * 1e18 / lp0Decimals;
            amountB = amountB * 1e18 / lp1Decimals;
            uint256 ratio = out0 * 1e18 / out1 * amountB / amountA;
            lp0Amt = nativeBal * 1e18 / (ratio + 1e18);
            lp1Amt = nativeBal - lp0Amt;
        }

        if (lpToken0 != swapToken) {
            if (useSolidlyFor0) ISolidlyRouter(unirouter).swapExactTokensForTokens(lp0Amt, 0, nativeToLp0Route, address(this), block.timestamp);
            else AlgebraUtils.swap(algebraRouter, nativeToLp0Path, lp0Amt);
        } 

        if (lpToken1 != swapToken) {
            if (useSolidlyFor1) ISolidlyRouter(unirouter).swapExactTokensForTokens(lp1Amt, 0, nativeToLp1Route, address(this), block.timestamp);
            else AlgebraUtils.swap(algebraRouter, nativeToLp1Path, lp1Amt);
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
        return IRewardPool(rewardPool).balanceOf(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public pure returns (uint256) {
        return 0;
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0;
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

        if (balanceOfPool() > 0) {
            if (IRewardPool(rewardPool).emergency()) IRewardPool(rewardPool).emergencyWithdraw();
            else IRewardPool(rewardPool).withdraw(balanceOfPool());
        }

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        if (IRewardPool(rewardPool).emergency()) IRewardPool(rewardPool).emergencyWithdraw();
        else IRewardPool(rewardPool).withdraw(balanceOfPool());
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
        IERC20(want).approve(rewardPool, type(uint).max);
        IERC20(output).approve(algebraRouter, type(uint).max);
        IERC20(native).approve(unirouter, type(uint).max);
        IERC20(native).approve(algebraRouter, type(uint).max);
        IERC20(paymentToken).approve(algebraRouter, type(uint).max);
        IERC20(paymentToken).approve(unirouter, type(uint).max);
        IERC20(paymentToken).approve(otoken, type(uint).max);

        IERC20(lpToken0).approve(unirouter, 0);
        IERC20(lpToken0).approve(unirouter, type(uint).max);
        IERC20(lpToken1).approve(unirouter, 0);
        IERC20(lpToken1).approve(unirouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).approve(rewardPool, 0);
        IERC20(output).approve(algebraRouter, 0);
        IERC20(native).approve(unirouter, 0);
        IERC20(native).approve(algebraRouter, 0);
        IERC20(paymentToken).approve(algebraRouter, 0);
        IERC20(paymentToken).approve(unirouter, 0);
        IERC20(paymentToken).approve(otoken, 0);

        IERC20(lpToken0).approve(unirouter, 0);
        IERC20(lpToken1).approve(unirouter, 0);
    }

    function setNativeToLp0(bytes calldata _nativeToLp0Path) public onlyOwner {
        if (_nativeToLp0Path.length > 0) {
            address[] memory route = AlgebraUtils.pathToRoute(_nativeToLp0Path);
            require(route[0] == native, "!native");
            require(route[route.length - 1] == lpToken0, "!lp0");
        }
        nativeToLp0Path = _nativeToLp0Path;
    }

    function setNativeToLp1(bytes calldata _nativeToLp1Path) public onlyOwner {
        if (_nativeToLp1Path.length > 0) {
            address[] memory route = AlgebraUtils.pathToRoute(_nativeToLp1Path);
            require(route[0] == native, "!native");
            require(route[route.length - 1] == lpToken1, "!lp1");
        }
        nativeToLp1Path = _nativeToLp1Path;
    }

    function nativeToLp0() external view returns (address[] memory) {
        return AlgebraUtils.pathToRoute(nativeToLp0Path);
    }

    function nativeToLp1() external view returns (address[] memory) {
        return AlgebraUtils.pathToRoute(nativeToLp1Path);
    }
}
