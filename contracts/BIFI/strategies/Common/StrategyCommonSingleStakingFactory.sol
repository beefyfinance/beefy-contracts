// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../../interfaces/beefy/IStrategyFactory.sol";
import "../../interfaces/common/IFeeConfig.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/common/IRewardPool.sol";

contract StrategyCommonSingleStakingFactory is OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    struct Addresses {
        address want;
        address depositToken;
        address factory;
        address vault;
        address swapper;
        address strategist;
    }

    address public output;
    mapping(address => uint) public minAmounts; // tokens minimum amount to be swapped

    string public stratName;
    IRewardPool public staking;

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
        if (paused() || factory.globalPause() || factory.strategyPause(stratName)) revert StrategyPaused();
        _;
    }

    modifier onlyManager() {
        _checkManager();
        _;
    }

    function _checkManager() internal view {
        if (msg.sender != owner() && msg.sender != keeper()) revert NotManager();
    }

    function initialize(
        string memory _stratName,
        IRewardPool _staking,
        address _output,
        Addresses calldata _addresses
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        stratName = _stratName;
        staking = _staking;
        output = _output;

        want = _addresses.want;
        factory = IStrategyFactory(_addresses.factory);
        vault = _addresses.vault;
        swapper = _addresses.swapper;
        strategist = _addresses.strategist;
        native = factory.native();
        setDepositToken(_addresses.depositToken);

        lockDuration = 1 days;
    }

    function balanceOfPool() public view returns (uint) {
        return staking.balanceOf(address(this));
    }

    function _deposit(uint amount) internal {
        IERC20(want).forceApprove(address(staking), amount);
        staking.stake(amount);
    }

    function _withdraw(uint amount) internal {
        if (amount > 0) {
            staking.withdraw(amount);
        }
    }

    function _emergencyWithdraw() internal {
        _withdraw(balanceOfPool());
    }

    function _claim() internal {
        staking.getReward();
    }

    function _verifyRewardToken(address token) internal view {}

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
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > minAmounts[output]) {
            _chargeFees(callFeeRecipient);

            _swapOutputToWant();
            uint256 wantHarvested = balanceOfWant();
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;

            if (!onDeposit) {
                deposit();
            }

            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function _chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = beefyFeeConfig().getFees(address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        uint256 toNative = outputBal * fees.total / DIVISOR;
        _swap(output, native, toNative);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient(), beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function _swapOutputToWant() internal virtual {
        if (depositToken == address(0)) {
            _swap(output, want);
        } else {
            if (depositToken != output) {
                _swap(output, depositToken);
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

    function rewardsLength() external pure returns (uint) {
        return 1;
    }

    function rewards(uint) external view returns (address) {
        return output;
    }

    receive () payable external {}

    uint256[49] private __gap;
}