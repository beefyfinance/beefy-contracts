// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/gmx/IGMXExchange.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyGM is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    // Tokens used
    address public want;
    address public native;
    address public long;
    address public short;
    address[] public rewards;

    // Third party contracts
    address public exchange;
    address public depositVault;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public duration;

    uint256 public storedBalance;
    uint256 public executionFee;
    uint256 public callbackGas;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function initialize(
        address _want,
        address _native,
        address _long,
        address _short,
        address _exchange,
        address _depositVault,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        __StratFeeManager_init(_commonAddresses);
        want = _want;
        native = _native;
        long = _long;
        short = _short;
        exchange = _exchange;
        depositVault = _depositVault;
        executionFee = 0.002 ether;
        callbackGas = 1_000_000;
        duration = 7 days;
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        require(msg.sender == vault, "!vault");

        storedBalance = balanceOfWant();
        emit Deposit(balanceOf());
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
        }

        storedBalance -= wantBal;
        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
        _sync();
    }

    function _sync() internal {
        if (balanceOfWant() > storedBalance) {
            uint256 wantHarvested = balanceOfWant() - storedBalance;
            storedBalance = balanceOfWant();
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        _swapRewardsToNative();
        if (IERC20(native).balanceOf(address(this)) > executionFee) {
            chargeFees(callFeeRecipient);
            _mintGm();
        }
    }

    // swap all rewards to native
    function _swapRewardsToNative() internal {
        for (uint i; i < rewards.length; ++i) {
            address reward = rewards[i];
            if (reward != native) {
                uint256 amount = IERC20(reward).balanceOf(address(this));
                if (amount > 0) {
                    IBeefySwapper(unirouter).swap(reward, native, amount);
                }
            }
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 feeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = feeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = feeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = feeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // mint GM tokens and await callback tx
    function _mintGm() internal {
        if (address(this).balance > 0) IWrappedNative(native).deposit{value: address(this).balance}();
        IERC20(native).transfer(depositVault, executionFee);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        uint256 halfAmount = nativeBal / 2;
        if (long != native) IBeefySwapper(unirouter).swap(native, long, halfAmount);
        if (short != native) IBeefySwapper(unirouter).swap(native, short, nativeBal - halfAmount);

        IERC20(long).transfer(depositVault, IERC20(long).balanceOf(address(this)));
        IERC20(short).transfer(depositVault, IERC20(short).balanceOf(address(this)));

        address[] memory path = new address[](0);
            
        IGMXExchange.CreateDepositParams memory params = IGMXExchange.CreateDepositParams({
            receiver: address(this),
            callbackContract: address(this),
            uiFeeReceiver: address(0),
            market: want,
            initialLongToken: long,
            initialShortToken: short,
            longTokenSwapPath: path,
            shortTokenSwapPath: path,
            minMarketTokens: 0,
            shouldUnwrapNativeToken: false,
            executionFee: executionFee,
            callbackGasLimit: callbackGas
        });

        IGMXExchange(exchange).createDeposit(params);
    }

    // receive permissionless callback to sync balances
    function afterDepositExecution(
        bytes32,
        IGMXExchange.Props memory,
        IGMXExchange.EventLogData memory
    ) external {
        _sync();
    }

    // receive permissionless callback when cancelling a deposit
    function afterDepositCancellation(
        bytes32,
        IGMXExchange.Props memory,
        IGMXExchange.EventLogData memory
    ) external {}

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return storedBalance - lockedProfit();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public pure returns (uint256) {
        return 0;
    }

    // lock profits to prevent front-running
    function lockedProfit() public view returns (uint256 left) {
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < duration ? duration - elapsed : 0;
        left = totalLocked * remaining / duration;
    }

    // returns rewards unharvested
    function rewardsAvailable() public pure returns (uint256) {
        return 0;
    }

    // native reward amount for calling harvest
    function callReward() public pure returns (uint256) {
        return 0;
    }

    // toggle harvesting on deposits
    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        storedBalance = 0;
        totalLocked = 0;
        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
    }

    function pause() public onlyManager {
        _pause();

        _removeAllowances();
    }

    function unpause() external onlyManager {
        _unpause();

        _giveAllowances();
    }

    function _giveAllowances() internal {
        IERC20(native).safeApprove(unirouter, type(uint).max);
        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, type(uint).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(native).safeApprove(unirouter, 0);
        for (uint i; i < rewards.length; ++i) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }
    }

    // cancel an active deposit
    function cancelDeposit(bytes32 _key) external onlyManager {
        IGMXExchange(exchange).cancelDeposit(_key);
    }

    function setRewards(address[] calldata _rewards) external onlyOwner {
        for (uint i; i < _rewards.length; ++i) {
            require(_rewards[i] != want, "!want");
        }
        _removeAllowances();
        rewards = _rewards;
        _giveAllowances();
    }

    function setExchange(address _exchange) external onlyOwner {
        exchange = _exchange;
    }

    function setDepositVault(address _depositVault) external onlyOwner {
        depositVault = _depositVault;
    }

    function setExecutionFee(uint256 _executionFee) external onlyManager {
        executionFee = _executionFee;
    }

    function setCallbackGas(uint256 _callbackGas) external onlyManager {
        callbackGas = _callbackGas;
    }

    function setDuration(uint256 _duration) external onlyManager {
        duration = _duration;
    }

    receive() external payable {}
}
