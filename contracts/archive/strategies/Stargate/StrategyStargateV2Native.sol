// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/stargate/IStargateV2Chef.sol";
import "../../interfaces/stargate/IStargateV2Router.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/common/IERC20Extended.sol";
import "../../interfaces/beefy/IBeefySwapper.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyStargateV2Native is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    address[] public rewards;
    mapping(address => uint) public minAmounts; // tokens minimum amount to be swapped

    address public want;
    address public native;
    address public lpToken;
    address[] internal lpTokens;
    uint256 public lastHarvest;
    uint256 public totalLocked;
    uint256 public lockDuration;
    bool public harvestOnDeposit;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    // Third party contracts
    address public chef;
    address public stargateRouter;
    uint256 public convertRate;

    function initialize(
        address _chef,
        address _stargateRouter,
        address _native,
        address[] calldata _rewards,
        CommonAddresses calldata _commonAddresses
    ) external initializer {
        __StratFeeManager_init(_commonAddresses);
        chef = _chef;
        stargateRouter = _stargateRouter;
        want = _native;
        lpToken = IStargateV2Router(stargateRouter).lpToken();
        lpTokens.push(lpToken);
        convertRate = 10 ** uint256(IERC20Extended(want).decimals() - IStargateV2Router(stargateRouter).sharedDecimals());
        native = _native;
        lockDuration = 1 days;
        for (uint i; i < _rewards.length; i++) {
            addReward(_rewards[i]);
        }
        setWithdrawalFee(0);
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();
        if (wantBal > 0) {
            uint256 amount = (wantBal / convertRate) * convertRate;
            if (amount > 0) {
                IWrappedNative(native).withdraw(amount);
                IStargateV2Router(stargateRouter).deposit{value: amount}(address(this), amount);
                IStargateV2Chef(chef).deposit(lpToken, amount);
                emit Deposit(balanceOf());
            }
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            uint256 amount = ((_amount - wantBal) / convertRate) * convertRate;
            IStargateV2Chef(chef).withdraw(lpToken, amount);
            IStargateV2Router(stargateRouter).redeem(amount, address(this));
            wantBal = balanceOfWant();
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

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
    }

    function claim() external {
        IStargateV2Chef(chef).claim(lpTokens);
    }

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        uint256 beforeBal = balanceOfWant();
        IStargateV2Chef(chef).claim(lpTokens);
        _swapRewardsToNative();
        uint256 nativeBal = balanceOfWant() - beforeBal;
        if (nativeBal > 0) {
            _chargeFees(callFeeRecipient, nativeBal);
            uint256 wantHarvested = balanceOfWant() - beforeBal;
            totalLocked = wantHarvested + lockedProfit();
            lastHarvest = block.timestamp;
            deposit();
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    function _swapRewardsToNative() internal virtual {
        for (uint i; i < rewards.length; ++i) {
            address token = rewards[i];
            uint256 amount = IERC20(token).balanceOf(address(this));
            if (amount > minAmounts[token]) {
                IBeefySwapper(unirouter).swap(token, native, amount);
            }
        }
    }

    // performance fees
    function _chargeFees(address callFeeRecipient, uint256 harvested) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 nativeBal = harvested * fees.total / DIVISOR;

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    function _swap(address tokenFrom, address tokenTo) internal {
        uint bal = IERC20(tokenFrom).balanceOf(address(this));
        IBeefySwapper(unirouter).swap(tokenFrom, tokenTo, bal);
    }

    function rewardsLength() external view returns (uint) {
        return rewards.length;
    }

    function addReward(address _token) public onlyManager {
        require(_token != want, "!want");
        require(_token != native, "!native");
        require(_token != lpToken, "!lpToken");

        rewards.push(_token);
        _approve(_token, unirouter, 0);
        _approve(_token, unirouter, type(uint).max);
    }

    function removeReward(uint i) external onlyManager {
        rewards[i] = rewards[rewards.length - 1];
        rewards.pop();
    }

    function resetRewards() external onlyManager {
        for (uint i; i < rewards.length; ++i) {
            _approve(rewards[i], unirouter, 0);
        }
        delete rewards;
    }

    function updateUnirouter(address _unirouter) external onlyOwner {
        for (uint i; i < rewards.length; ++i) {
            address token = rewards[i];
            _approve(token, unirouter, 0);
            _approve(token, _unirouter, 0);
            _approve(token, _unirouter, type(uint).max);
        }
        _approve(native, unirouter, 0);
        _approve(native, _unirouter, 0);
        _approve(native, _unirouter, type(uint).max);
        unirouter = _unirouter;
        emit SetUnirouter(_unirouter);
    }

    function setRewardMinAmount(address token, uint minAmount) external onlyManager {
        minAmounts[token] = minAmount;
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

    function balanceOfPool() public view returns (uint256) {
        return IStargateV2Chef(chef).balanceOf(lpToken, address(this));
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

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");
        IStargateV2Chef(chef).emergencyWithdraw(lpToken);
        IStargateV2Router(stargateRouter).redeem(IERC20(lpToken).balanceOf(address(this)), address(this));
        IERC20(want).transfer(vault, balanceOfWant());
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IStargateV2Chef(chef).emergencyWithdraw(lpToken);
        IStargateV2Router(stargateRouter).redeem(IERC20(lpToken).balanceOf(address(this)), address(this));
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

    function _approve(address _token, address _spender, uint amount) internal {
        IERC20(_token).safeApprove(_spender, amount);
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(stargateRouter, type(uint256).max);
        IERC20(lpToken).safeApprove(chef, type(uint256).max);

        for (uint i; i < rewards.length; i++) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
            IERC20(rewards[i]).safeApprove(unirouter, type(uint256).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(stargateRouter, 0);
        IERC20(lpToken).safeApprove(chef, 0);

        for (uint i; i < rewards.length; i++) {
            IERC20(rewards[i]).safeApprove(unirouter, 0);
        }
    }

    receive() external payable {
        if (msg.sender != native) IWrappedNative(native).deposit{value: address(this).balance}();
    }
}
