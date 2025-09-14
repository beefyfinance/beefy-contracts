// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IBaseAllToNativeFactoryStratNew } from "../Interfaces/IBaseAllToNativeFactoryStratNew.sol";
import { BaseAllToNativeFactoryStorageUtils } from "../Storage/BaseAllToNativeFactoryStratStorage.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { SafeERC20, IERC20 } from "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import { IBeefySwapper } from "../../../interfaces/beefy/IBeefySwapper.sol";
import { IStrategyFactory } from "../../../interfaces/beefy/IStrategyFactory.sol";
import { IFeeConfig } from "../../../interfaces/common/IFeeConfig.sol";
import { IWrappedNative } from "../../../interfaces/common/IWrappedNative.sol";

abstract contract BaseAllToNativeFactoryStratNew is IBaseAllToNativeFactoryStratNew, BaseAllToNativeFactoryStorageUtils, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;
    // @dev constant for divisor 1 ether
    uint256 constant DIVISOR = 1 ether;
    // @dev constant for making raw native address
    address constant NATIVE = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // @dev modifier to check if the strategy is paused
    modifier ifNotPaused() {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if (paused() || IStrategyFactory($.addresses.factory).globalPause() || IStrategyFactory($.addresses.factory).strategyPause(stratName())) revert StrategyPaused();
        _;
    }

    // @dev modifier to check if the caller is the owner or the keeper
    modifier onlyManager() {
        _checkManager();
        _;
    }

    // @dev function to check if the caller is the owner or the keeper
    function _checkManager() internal view {
        if (msg.sender != owner() && msg.sender != keeper()) revert NotManager();
    }

    // @dev function to initialize the strategy
    function __BaseStrategy_init(Addresses memory _addresses, address[] memory _rewards) internal onlyInitializing {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        __Ownable_init();
        __Pausable_init();
        $.addresses = _addresses; 
        $.native = IStrategyFactory($.addresses.factory).native();

        for (uint i; i < _rewards.length; ++i) {
            addReward(_rewards[i]);
        }
        setDepositToken(_addresses.depositToken);

        $.lockDuration = 1 days;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function stratName() public view virtual returns (string memory);

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function balanceOfPool() public view virtual returns (uint);

    // @dev internal logic function to deposit funds into the strategy
    function _deposit(uint _amount) internal virtual;

    // @dev internal logic function to withdraw funds from the strategy
    function _withdraw(uint _amount) internal virtual;

    // @dev internal logic function to withdraw funds from the strategy
    function _emergencyWithdraw() internal virtual;

    // @dev internal logic function to claim rewards
    function _claim() internal virtual;

    // @dev internal logic function to verify reward token
    function _verifyRewardToken(address _token) internal view virtual;

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function deposit() public ifNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            _deposit(wantBal);
            emit Deposit(balanceOf());
        }
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function withdraw(uint256 _amount) external {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if(msg.sender != $.addresses.vault) revert NotVault();

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            _withdraw(_amount - wantBal);
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        IERC20($.addresses.want).safeTransfer($.addresses.vault, wantBal);

        emit Withdraw(balanceOf());
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function beforeDeposit() external virtual {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if ($.harvestOnDeposit) {
            if(msg.sender != $.addresses.vault) revert NotVault();
            _harvest(tx.origin, true);
        }
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function claim() external virtual {
        _claim();
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function harvest() external virtual {
        _harvest(tx.origin, false);
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function harvest(address _callFeeRecipient) external virtual {
        _harvest(_callFeeRecipient, false);
    }

    // @notice internal logic function to harvest rewards
    // @param _callFeeRecipient the address to send the call fees to
    // @param _onDeposit whether the harvest is called on deposit
    function _harvest(address _callFeeRecipient, bool _onDeposit) internal ifNotPaused {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        _claim();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20($.native).balanceOf(address(this));
        if (nativeBal > $.minAmounts[$.native]) {
            _chargeFees(_callFeeRecipient);

            _swapNativeToWant();
            uint256 wantHarvested = balanceOfWant();
            $.totalLocked = wantHarvested + lockedProfit();
            $.lastHarvest = block.timestamp;

            if (!_onDeposit) {
                deposit();
            }

            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // @notice internal logic function to swap rewards to native
    // @dev this function is virtual to allow for custom logic in the strategy
    function _swapRewardsToNative() internal virtual {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        for (uint i; i < $.rewards.length; ++i) {
            address token = $.rewards[i];
            if (token == NATIVE) {
                IWrappedNative($.native).deposit{value: address(this).balance}();
            } else {
                uint amount = IERC20(token).balanceOf(address(this));
                if (amount > $.minAmounts[token]) {
                    _swap(token, $.native, amount);
                }
            }
        }
    }

    // @notice internal logic function to charge fees
    function _chargeFees(address _callFeeRecipient) internal {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        IFeeConfig.FeeCategory memory fees = beefyFeeConfig().getFees(address(this));
        uint256 nativeFees = IERC20($.native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeFees * fees.call / DIVISOR;
        IERC20($.native).safeTransfer(_callFeeRecipient, callFeeAmount);

        uint256 strategistFeeAmount = nativeFees * fees.strategist / DIVISOR;
        IERC20($.native).safeTransfer($.addresses.strategist, strategistFeeAmount);

        uint256 beefyFeeAmount = nativeFees - callFeeAmount - strategistFeeAmount;
        IERC20($.native).safeTransfer(beefyFeeRecipient(), beefyFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // @notice internal logic function to swap native to want
    function _swapNativeToWant() internal virtual {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if ($.addresses.depositToken == address(0)) {
            _swap($.native, $.addresses.want);
        } else {
            if ($.addresses.depositToken != $.native) {
                _swap($.native, $.addresses.depositToken);
            }
            _swap($.addresses.depositToken, $.addresses.want);
        }
    }

    // @notice internal logic function to swap tokens
    function _swap(address _tokenFrom, address _tokenTo) internal {
        uint bal = IERC20(_tokenFrom).balanceOf(address(this));
        _swap(_tokenFrom, _tokenTo, bal);
    }

    // @notice internal logic function to swap tokens
    function _swap(address _tokenFrom, address _tokenTo, uint _amount) internal {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if (_tokenFrom != _tokenTo) {
            IERC20(_tokenFrom).forceApprove($.addresses.swapper, _amount);
            IBeefySwapper($.addresses.swapper).swap(_tokenFrom, _tokenTo, _amount);
        }
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function rewardsLength() external view returns (uint) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.rewards.length;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function addReward(address _token) public onlyManager {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if (_token == $.addresses.want) revert NotWant();
        if (_token == $.native) revert NotNative();
        _verifyRewardToken(_token);
        $.rewards.push(_token);
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function removeReward(uint i) external onlyManager {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        $.rewards[i] = $.rewards[$.rewards.length - 1];
        $.rewards.pop();
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function resetRewards() external onlyManager {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();  
        delete $.rewards;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function setRewardMinAmount(address token, uint minAmount) external onlyManager {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        $.minAmounts[token] = minAmount;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function setDepositToken(address _token) public onlyManager {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if (_token == address(0)) {
            $.addresses.depositToken = address(0);
            return;
        }
        if (_token == $.addresses.want) revert NotWant();
        _verifyRewardToken(_token);
        $.addresses.depositToken = _token;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function lockedProfit() public view returns (uint256) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if ($.lockDuration == 0) return 0;
        uint256 elapsed = block.timestamp - $.lastHarvest;
        uint256 remaining = elapsed < $.lockDuration ? $.lockDuration - elapsed : 0;
        return $.totalLocked * remaining / $.lockDuration;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool() - lockedProfit();
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function balanceOfWant() public view returns (uint256) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return IERC20($.addresses.want).balanceOf(address(this));
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyManager {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        $.harvestOnDeposit = _harvestOnDeposit;
        if ($.harvestOnDeposit) {
            $.lockDuration = 0;
        } else {
            $.lockDuration = 1 days;
        }
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function setLockDuration(uint _duration) external onlyManager {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        $.lockDuration = _duration;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function rewardsAvailable() external view virtual returns (uint) {
        return 0;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function callReward() external view virtual returns (uint) {
        return 0;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function depositFee() public view virtual returns (uint) {
        return 0;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function withdrawFee() public view virtual returns (uint) {
        return 0;
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function retireStrat() external {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if (msg.sender != $.addresses.vault) revert NotVault();
        _emergencyWithdraw();
        IERC20($.addresses.want).transfer($.addresses.vault, balanceOfWant());
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function panic() public virtual onlyManager {
        pause();
        _emergencyWithdraw();
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function pause() public virtual onlyManager {
        _pause();
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function unpause() external virtual onlyManager {
        _unpause();
        deposit();
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function keeper() public view returns (address) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return IStrategyFactory($.addresses.factory).keeper();
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function beefyFeeConfig() public view returns (IFeeConfig) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return IFeeConfig(IStrategyFactory($.addresses.factory).beefyFeeConfig());
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function beefyFeeRecipient() public view returns (address) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return IStrategyFactory($.addresses.factory).beefyFeeRecipient();
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function getAllFees() external view returns (IFeeConfig.AllFees memory) {
        return IFeeConfig.AllFees(beefyFeeConfig().getFees(address(this)), depositFee(), withdrawFee());
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function setVault(address _vault) external onlyOwner {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        $.addresses.vault = _vault;
        emit SetVault(_vault);
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function setSwapper(address _swapper) external onlyOwner {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        $.addresses.swapper = _swapper;
        emit SetSwapper(_swapper);
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function setStrategist(address _strategist) external {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        if (msg.sender != $.addresses.strategist) revert NotStrategist();
        $.addresses.strategist = _strategist;
        emit SetStrategist(_strategist);
    }

    // @inheritdoc IBaseAllToNativeFactoryStratNew
    function want() public view returns (address) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.addresses.want;
    }

    function depositToken() public view returns (address) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.addresses.depositToken;
    }

    function factory() public view returns (address) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.addresses.factory;
    }

    function vault() public view returns (address) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.addresses.vault;
    }

    function swapper() public view returns (address) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.addresses.swapper;
    }

    function strategist() public view returns (address) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.addresses.strategist;
    }

    function native() public view returns (address) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.native;
    }

    function rewards() public view returns (address[] memory) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.rewards;
    }

    function lastHarvest() public view returns (uint) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.lastHarvest;
    }

    function totalLocked() public view returns (uint) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.totalLocked;
    }

    function lockDuration() public view returns (uint) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.lockDuration;
    }

    function harvestOnDeposit() public view returns (bool) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.harvestOnDeposit;
    }

    function minAmounts(address token) public view returns (uint) {
        BaseAllToNativeFactoryStratStorage storage $ = getBaseAllToNativeFactoryStratStorage();
        return $.minAmounts[token];
    }

    receive () payable external {}
}