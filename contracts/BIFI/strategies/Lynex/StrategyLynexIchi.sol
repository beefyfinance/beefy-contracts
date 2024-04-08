// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/ichi/IIchiDepositHelper.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../Common/StratFeeManagerInitializable.sol";
import "../../utils/GasFeeThrottler.sol";
import "../../utils/AlgebraUtils.sol";

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

contract StrategyLynexIchi is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public constant native = 0xe5D7C2a44FfDDf6b295A15c148167daaAf5Cf34f;
    address public constant output = 0x1a51b19CE03dbE0Cb44C1528E34a7EDD7771E9Af;
    address public constant otoken = 0x63349BA5E1F71252eCD56E8F950D1A518B400b60;
    address public constant paymentToken = 0x176211869cA2b568f2A7D4EE941E073a821EE1ff;
    address public constant flashPool = 0xa4477d98e519D4c1d66aEf4EfDF7cBEb84f4f778;
    address public constant ichiDepositHelper = 0x57C9d919AEA56171506cfb62B60ce76be0A079DF;
    address public constant vaultDeployer = 0x75178e0a2829B73E3AE4C21eE64F4B684085392a;
    address public constant pairFactory = 0xBc7695Fd00E3b32D08124b7a4287493aEE99f9ee;

    address public want;
    address public depositToken;

    // Third party contracts
    address public rewardPool;

    bool public harvestOnDeposit;
    bool private flashOn;
    uint256 public lastHarvest;

    bytes public outputToPaymentPath;
    bytes public paymentToNativePath;
    bytes public nativeToDepositPath;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _rewardPool,
        address[] calldata _outputToPaymentRoute,
        address[] calldata _paymentToNativeRoute,
        address[] calldata _nativeToDepositRoute,
        CommonAddresses calldata _commonAddresses
     ) public initializer  {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        rewardPool = _rewardPool;
        depositToken = _nativeToDepositRoute[_nativeToDepositRoute.length - 1];

        outputToPaymentPath = AlgebraUtils.routeToPath(_outputToPaymentRoute);
        paymentToNativePath = AlgebraUtils.routeToPath(_paymentToNativeRoute);
        nativeToDepositPath = AlgebraUtils.routeToPath(_nativeToDepositRoute);

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
        AlgebraUtils.swap(unirouter, outputToPaymentPath, outputTokenBal);

        uint256 debt = amount0 + getTotalFlashFee(amount0);
        IERC20(paymentToken).safeTransfer(flashPool, debt);

        uint256 paymentTokenBal = IERC20(paymentToken).balanceOf(address(this));
        AlgebraUtils.swap(unirouter, paymentToNativePath, paymentTokenBal);
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
        if (depositToken != native) {
            uint256 nativeBal = IERC20(native).balanceOf(address(this));
            AlgebraUtils.swap(unirouter, nativeToDepositPath, nativeBal);
        }

        uint256 depositTokenBal = IERC20(depositToken).balanceOf(address(this));
        IIchiDepositHelper(ichiDepositHelper).forwardDepositToICHIVault(
            want, vaultDeployer, depositToken, depositTokenBal, 0, address(this)
        );
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
        IERC20(output).approve(unirouter, type(uint).max);
        IERC20(native).approve(unirouter, type(uint).max);
        IERC20(paymentToken).approve(unirouter, type(uint).max);
        IERC20(paymentToken).approve(otoken, type(uint).max);
        IERC20(depositToken).safeApprove(ichiDepositHelper, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).approve(rewardPool, 0);
        IERC20(output).approve(unirouter, 0);
        IERC20(native).approve(unirouter, 0);
        IERC20(paymentToken).approve(unirouter, 0);
        IERC20(paymentToken).approve(otoken, 0);
        IERC20(depositToken).safeApprove(ichiDepositHelper, 0);
    }

    function outputToPayment() external view returns (address[] memory) {
        return AlgebraUtils.pathToRoute(outputToPaymentPath);
    }

    function paymentToNative() external view returns (address[] memory) {
        return AlgebraUtils.pathToRoute(paymentToNativePath);
    }

    function nativeToDeposit() external view returns (address[] memory) {
        return AlgebraUtils.pathToRoute(nativeToDepositPath);
    }
}
