// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/ISolidlyPair.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/lynex/ILynexRewardPool.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/GasFeeThrottler.sol";

interface IGammaUniProxy {
    function getDepositAmount(address pos, address token, uint _deposit) external view returns (uint amountStart, uint amountEnd);
    function deposit(uint deposit0, uint deposit1, address to, address pos, uint[4] memory minIn) external returns (uint shares);
}

interface IAlgebraPool {
    function pool() external view returns(address);
    function globalState() external view returns(uint);
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

contract StrategyLynexGamma is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public constant native = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;
    address public constant output = 0x1a51b19CE03dbE0Cb44C1528E34a7EDD7771E9Af;
    address public constant otoken = 0x63349BA5E1F71252eCD56E8F950D1A518B400b60;
    address public constant paymentToken = 0x176211869cA2b568f2A7D4EE941E073a821EE1ff;
    address public constant flashPool = 0xa4477d98e519D4c1d66aEf4EfDF7cBEb84f4f778;
    address public constant pairFactory = 0xBc7695Fd00E3b32D08124b7a4287493aEE99f9ee;

    address public want;
    address public lpToken0;
    address public lpToken1;
    address[] public rewards;

    // Third party contracts
    address public rewardPool;

    bool public isFastQuote;
    bool public harvestOnDeposit;
    bool private flashOn;
    uint256 public lastHarvest;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _rewardPool,
        CommonAddresses calldata _commonAddresses
     ) public initializer  {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        rewardPool = _rewardPool;

        lpToken0 = ISolidlyPair(want).token0();
        lpToken1 = ISolidlyPair(want).token1();

        rewards.push(otoken);

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            ILynexRewardPool(rewardPool).deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ILynexRewardPool(rewardPool).withdraw(_amount - wantBal);
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
        ILynexRewardPool(rewardPool).getReward(address(this), rewards);
        _swapRewards();
        if (IERC20(native).balanceOf(address(this)) > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _swapRewards() internal {
        uint256 outputBal = IERC20(otoken).balanceOf(address(this));
        if (outputBal > 0) flashExercise(outputBal);

        for (uint i; i < rewards.length; ++i) {
            address reward = rewards[i];
            uint256 rewardBal = IERC20(reward).balanceOf(address(this));
            if (rewardBal > 0) IBeefySwapper(unirouter).swap(reward, native, rewardBal);
        }
    }

    function hook(address sender, uint256 amount0, uint256, bytes memory) external {
        require(sender == address(this), "wrong sender");
        require(msg.sender == flashPool, "!flashPool");
        require(flashOn, "!flashOn");

        uint256 oTokenBal = IERC20(otoken).balanceOf(address(this));
        IOptionsToken(otoken).exercise(oTokenBal, amount0, address(this), block.timestamp);

        uint256 outputTokenBal = IERC20(output).balanceOf(address(this));
        IBeefySwapper(unirouter).swap(output, paymentToken, outputTokenBal);

        uint256 debt = amount0 + getTotalFlashFee(amount0);
        IERC20(paymentToken).safeTransfer(flashPool, debt);

        uint256 paymentTokenBal = IERC20(paymentToken).balanceOf(address(this));
        IBeefySwapper(unirouter).swap(paymentToken, native, paymentTokenBal);
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
        (uint toLp0, uint toLp1) = quoteAddLiquidity();

        if (lpToken0 != native) IBeefySwapper(unirouter).swap(native, lpToken0, toLp0);
        if (lpToken1 != native) IBeefySwapper(unirouter).swap(native, lpToken1, toLp1);

        uint256 lp0Bal = IERC20(lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(lpToken1).balanceOf(address(this));

        (uint amount1Start, uint amount1End) = gammaProxy().getDepositAmount(want, lpToken0, lp0Bal);
        if (lp1Bal > amount1End) {
            lp1Bal = amount1End;
        } else if (lp1Bal < amount1Start) {
            (, lp0Bal) = gammaProxy().getDepositAmount(want, lpToken1, lp1Bal);
        }

        uint[4] memory minIn;
        gammaProxy().deposit(lp0Bal, lp1Bal, address(this), want, minIn);
    }

    function quoteAddLiquidity() internal view returns (uint toLp0, uint toLp1) {
        uint nativeBal = IERC20(native).balanceOf(address(this));
        uint ratio;

        if (isFastQuote) {
            uint lp0Decimals = 10**IERC20Extended(lpToken0).decimals();
            uint lp1Decimals = 10**IERC20Extended(lpToken1).decimals();
            uint decimalsDiff = 1e18 * lp0Decimals / lp1Decimals;
            uint decimalsDenominator = decimalsDiff > 1e12 ? 1e6 : 1;
            uint sqrtPriceX96 = IAlgebraPool(IAlgebraPool(want).pool()).globalState();
            uint price = sqrtPriceX96 ** 2 * (decimalsDiff / decimalsDenominator) / (2 ** 192) * decimalsDenominator;
            (uint amountStart, uint amountEnd) = gammaProxy().getDepositAmount(want, lpToken0, lp0Decimals);
            uint amountB = (amountStart + amountEnd) / 2 * 1e18 / lp1Decimals;
            ratio = amountB * 1e18 / price;
        } else {
            uint lp0Amt = nativeBal / 2;
            uint lp1Amt = nativeBal - lp0Amt;
            uint out0 = lp0Amt;
            uint out1 = lp1Amt;
            if (lpToken0 != native) out0 = IBeefySwapper(unirouter).getAmountOut(native, lpToken0, lp0Amt);
            if (lpToken1 != native) out1 = IBeefySwapper(unirouter).getAmountOut(native, lpToken1, lp1Amt);
            (uint amountStart, uint amountEnd) = gammaProxy().getDepositAmount(want, lpToken0, out0);
            uint amountB = (amountStart + amountEnd) / 2;
            ratio = amountB * 1e18 / out1;
        }

        toLp0 = nativeBal * 1e18 / (ratio + 1e18);
        toLp1 = nativeBal - toLp0;
    }

    function setFastQuote(bool _isFastQuote) external onlyManager {
        isFastQuote = _isFastQuote;
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
        return ILynexRewardPool(rewardPool).balanceOf(address(this));
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
            if (ILynexRewardPool(rewardPool).emergency()) ILynexRewardPool(rewardPool).emergencyWithdraw();
            else ILynexRewardPool(rewardPool).withdraw(balanceOfPool());
        }

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        if (ILynexRewardPool(rewardPool).emergency()) ILynexRewardPool(rewardPool).emergencyWithdraw();
        else ILynexRewardPool(rewardPool).withdraw(balanceOfPool());
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

    function addReward(address _reward) external onlyManager {
        require(_reward != want, "reward=want");
        rewards.push(_reward);

        if (!paused()) IERC20(_reward).approve(unirouter, type(uint).max);
    }

    function resetReward() external onlyManager {
        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).approve(unirouter, 0);
        }

        delete rewards;
        rewards.push(otoken);
    }

    function _giveAllowances() internal {
        IERC20(want).approve(rewardPool, type(uint).max);
        IERC20(output).approve(unirouter, type(uint).max);
        IERC20(native).approve(unirouter, type(uint).max);
        IERC20(paymentToken).approve(unirouter, type(uint).max);
        IERC20(paymentToken).approve(otoken, type(uint).max);

        IERC20(lpToken0).approve(want, 0);
        IERC20(lpToken0).approve(want, type(uint).max);
        IERC20(lpToken1).approve(want, 0);
        IERC20(lpToken1).approve(want, type(uint).max);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).approve(unirouter, type(uint).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(want).approve(rewardPool, 0);
        IERC20(output).approve(unirouter, 0);
        IERC20(native).approve(unirouter, 0);
        IERC20(paymentToken).approve(unirouter, 0);
        IERC20(paymentToken).approve(otoken, 0);

        IERC20(lpToken0).approve(want, 0);
        IERC20(lpToken1).approve(want, 0);

        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).approve(unirouter, 0);
        }
    }

    function gammaProxy() public view returns (IGammaUniProxy uniProxy) {
        uniProxy = IGammaUniProxy(IHypervisor(want).whitelistedAddress());
    }
}
