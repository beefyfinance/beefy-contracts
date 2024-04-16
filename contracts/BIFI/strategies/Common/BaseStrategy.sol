// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeERC20Upgradeable, IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { IWrappedNative } from  "../../interfaces/common/IWrappedNative.sol";
import "./StrategySwapper.sol";
import "./StratFeeManagerInitializable.sol";

abstract contract BaseStrategy is StrategySwapper, StratFeeManagerInitializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct BaseStrategyAddresses {
        address want;
        address native;
        address[] rewards;
        address beefySwapper;
    }

    address public want;
    address public native;
    address[] public depositTokens;

    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public lockDuration;
    bool public harvestOnDeposit;

    address[] public rewards;
    mapping(address => uint256) public minAmounts; // tokens minimum amount to be swapped

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    function __BaseStrategy_init(
        BaseStrategyAddresses calldata _baseStrategyAddresses,
        CommonAddresses calldata _commonAddresses
    ) internal onlyInitializing {
        __StratFeeManager_init(_commonAddresses);
        __StrategySwapper_init(_baseStrategyAddresses.beefySwapper);
        want = _baseStrategyAddresses.want;
        native = _baseStrategyAddresses.native;

        for (uint i; i < _baseStrategyAddresses.rewards.length; i++) {
            addReward(_baseStrategyAddresses.rewards[i]);
        }

        lockDuration = 6 hours;
        withdrawalFee = 0;
    }

    function balanceOfPool() public view virtual returns (uint256);
    function rewardsAvailable() external view virtual returns (uint256);
    function callReward() external view virtual returns (uint256);

    function _deposit(uint256 amount) internal virtual;
    function _withdraw(uint256 amount) internal virtual;
    function _emergencyWithdraw() internal virtual;
    function _claim() internal virtual;
    function _getDepositAmounts() internal virtual view returns (uint256[] memory);
    function _addLiquidity() internal virtual;
    function _verifyRewardToken(address _token) internal view virtual;

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            _deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            _withdraw(_amount - wantBal);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20Upgradeable(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
    }

    function harvest() external {
        _harvest(tx.origin, false);
    }

    function harvest(address callFeeRecipient) external {
        _harvest(callFeeRecipient, false);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient, bool onDeposit) internal whenNotPaused {
        uint256 wantBalanceBefore = balanceOfWant();
        _claim();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this));
        if (nativeBal > minAmounts[native]) {
            _chargeFees(callFeeRecipient);
            _swapNativeToWant();
            uint256 wantHarvested = balanceOfWant() - wantBalanceBefore;
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;

            if (!onDeposit) {
                deposit();
            }

            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _swapRewardsToNative() internal virtual {
        for (uint i; i < rewards.length; ++i) {
            address token = rewards[i];
            if (token == address(0)) {
                IWrappedNative(native).deposit{value: address(this).balance}();
            } else {
                uint256 amount = IERC20Upgradeable(token).balanceOf(address(this));
                if (amount > minAmounts[token]) {
                    IERC20Upgradeable(token).forceApprove(address(beefySwapper), amount);
                    _swap(token, native, amount);
                }
            }
        }
    }

    // performance fees
    function _chargeFees(address _callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = IERC20Upgradeable(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(_callFeeRecipient, callFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20Upgradeable(native).safeTransfer(strategist, strategistFeeAmount);

        uint256 beefyFeeAmount = nativeBal - callFeeAmount - strategistFeeAmount;
        IERC20Upgradeable(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function _swapNativeToWant() internal virtual {
        uint256[] memory amounts = _getDepositAmounts();
        for (uint i; i < depositTokens.length; ++i) {
            if (depositTokens[i] != native && amounts[i] > 0) {
                IERC20Upgradeable(native).forceApprove(address(beefySwapper), amounts[i]);
                _swap(native, depositTokens[i], amounts[i]);
            }
        }
        _addLiquidity();
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    function addReward(address _token) public onlyManager {
        _verifyRewardToken(_token);
        rewards.push(_token);
    }

    function removeReward(uint256 i) external onlyManager {
        rewards[i] = rewards[rewards.length - 1];
        rewards.pop();
    }

    function resetRewards() external onlyManager {
        delete rewards;
    }

    function setMinAmount(address _token, uint256 _minAmount) external onlyManager {
        minAmounts[_token] = _minAmount;
    }

    function lockedProfit() public view returns (uint256) {
        if (lockDuration == 0) return 0;
        uint256 elapsed = block.timestamp - lastHarvest;
        uint256 remaining = elapsed < lockDuration ? lockDuration - elapsed : 0;
        return totalLocked * remaining / lockDuration;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20Upgradeable(want).balanceOf(address(this));
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function setLockDuration(uint _duration) external onlyManager {
        lockDuration = _duration;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _emergencyWithdraw();
        IERC20Upgradeable(want).transfer(vault, balanceOfWant());
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        _emergencyWithdraw();
    }

    function pause() public onlyManager {
        _pause();
    }

    function unpause() external onlyManager {
        _unpause();
        deposit();
    }

    receive () payable external {}
}