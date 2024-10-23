// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/beefy/IStrategyFactory.sol";
import "../../interfaces/common/IFeeConfig.sol";
import "../../interfaces/common/IWrappedNative.sol";

abstract contract BaseAllToNativeFactoryStrat is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    struct Addresses {
        address want;
        address depositToken;
        address factory;
        address vault;
        address swapper;
        address strategist;
    }

    address[] public rewards;
    mapping(address => uint) public minAmounts; // tokens minimum amount to be swapped

    IStrategyFactory public factory;
    address public vault;
    address public swapper;
    address public strategist;

    address public want;
    address public native;
    address public depositToken;
    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public lockDuration;
    bool public harvestOnDeposit;

    uint256 constant DIVISOR = 1 ether;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);
    event SetVault(address vault);
    event SetSwapper(address swapper);
    event SetStrategist(address strategist);

    error StrategyPaused();
    error NotManager();

    modifier ifNotPaused() {
        if (paused() || factory.globalPause() || factory.strategyPause(stratName())) revert StrategyPaused();
        _;
    }

    modifier onlyManager() {
        _checkManager();
        _;
    }

    function _checkManager() internal view {
        if (msg.sender != owner() && msg.sender != keeper()) revert NotManager();
    }

    function __BaseStrategy_init(Addresses calldata _addresses, address[] calldata _rewards) internal onlyInitializing {
        __Ownable_init();
        __Pausable_init();
        want = _addresses.want;
        factory = IStrategyFactory(_addresses.factory);
        vault = _addresses.vault;
        swapper = _addresses.swapper;
        strategist = _addresses.strategist;
        native = factory.native();

        for (uint i; i < _rewards.length; i++) {
            addReward(_rewards[i]);
        }
        setDepositToken(_addresses.depositToken);

        lockDuration = 1 days;
    }

    function stratName() public view virtual returns (string memory);

    function balanceOfPool() public view virtual returns (uint);

    function _deposit(uint amount) internal virtual;

    function _withdraw(uint amount) internal virtual;

    function _emergencyWithdraw() internal virtual;

    function _claim() internal virtual;

    function _verifyRewardToken(address token) internal view virtual;

    // puts the funds to work
    function deposit() public ifNotPaused {
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

        IERC20(want).safeTransfer(vault, wantBal);

        emit Withdraw(balanceOf());
    }

    function beforeDeposit() external virtual {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin, true);
        }
    }

    function claim() external virtual {
        _claim();
    }

    function harvest() external virtual {
        _harvest(tx.origin, false);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient, false);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient, bool onDeposit) internal ifNotPaused {
        _claim();
        _swapRewardsToNative();
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        if (nativeBal > minAmounts[native]) {
            _chargeFees(callFeeRecipient);

            _swapNativeToWant();
            uint256 wantHarvested = balanceOfWant();
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
            if (token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
                IWrappedNative(native).deposit{value: address(this).balance}();
            } else {
                uint amount = IERC20(token).balanceOf(address(this));
                if (amount > minAmounts[token]) {
                    _swap(token, native, amount);
                }
            }
        }
    }

    // performance fees
    function _chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = beefyFeeConfig().getFees(address(this));
        uint256 nativeBal = IERC20(native).balanceOf(address(this)) * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient(), beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function _swapNativeToWant() internal virtual {
        if (depositToken == address(0)) {
            _swap(native, want);
        } else {
            if (depositToken != native) {
                _swap(native, depositToken);
            }
            _swap(depositToken, want);
        }
    }

    function _swap(address tokenFrom, address tokenTo) internal {
        uint bal = IERC20(tokenFrom).balanceOf(address(this));
        _swap(tokenFrom, tokenTo, bal);
    }

    function _swap(address tokenFrom, address tokenTo, uint amount) internal {
        IERC20(tokenFrom).forceApprove(swapper, amount);
        IBeefySwapper(swapper).swap(tokenFrom, tokenTo, amount);
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    function addReward(address _token) public onlyManager {
        require(_token != want, "!want");
        require(_token != native, "!native");
        _verifyRewardToken(_token);
        rewards.push(_token);
    }

    function removeReward(uint i) external onlyManager {
        rewards[i] = rewards[rewards.length - 1];
        rewards.pop();
    }

    function resetRewards() external onlyManager {
        delete rewards;
    }

    function setRewardMinAmount(address token, uint minAmount) external onlyManager {
        minAmounts[token] = minAmount;
    }

    function setDepositToken(address token) public onlyManager {
        if (token == address(0)) {
            depositToken = address(0);
            return;
        }
        require(token != want, "!want");
        _verifyRewardToken(token);
        depositToken = token;
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
        return IERC20(want).balanceOf(address(this));
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) public onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
        if (harvestOnDeposit) {
            lockDuration = 0;
        } else {
            lockDuration = 1 days;
        }
    }

    function setLockDuration(uint _duration) external onlyManager {
        lockDuration = _duration;
    }

    function rewardsAvailable() external view virtual returns (uint) {
        return 0;
    }

    function callReward() external view virtual returns (uint) {
        return 0;
    }

    function depositFee() public view virtual returns (uint) {
        return 0;
    }

    function withdrawFee() public view virtual returns (uint) {
        return 0;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        _emergencyWithdraw();
        IERC20(want).transfer(vault, balanceOfWant());
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public virtual onlyManager {
        pause();
        _emergencyWithdraw();
    }

    function pause() public virtual onlyManager {
        _pause();
    }

    function unpause() external virtual onlyManager {
        _unpause();
        deposit();
    }

    function keeper() public view returns (address) {
        return factory.keeper();
    }

    function beefyFeeConfig() public view returns (IFeeConfig) {
        return IFeeConfig(factory.beefyFeeConfig());
    }

    function beefyFeeRecipient() public view returns (address) {
        return factory.beefyFeeRecipient();
    }

    function getAllFees() external view returns (IFeeConfig.AllFees memory) {
        return IFeeConfig.AllFees(beefyFeeConfig().getFees(address(this)), depositFee(), withdrawFee());
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
        emit SetVault(_vault);
    }

    function setSwapper(address _swapper) external onlyOwner {
        swapper = _swapper;
        emit SetSwapper(_swapper);
    }

    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
        emit SetStrategist(_strategist);
    }

    receive () payable external {}

    uint256[49] private __gap;
}