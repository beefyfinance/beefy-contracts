// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/quick/IRewardPool.sol";
import "../../interfaces/quick/IDragonsLair.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";


pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;
contract StrategyQuickDragonsLair is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address constant public QUICK = address(0x831753DD7087CaC61aB5644b308642cc1c33Dc13);

    // Third party contracts
    address public rewardPool;
    address constant public dragonsLair = address(0xf28164A485B0B2C90639E47b0f377b4a438a16B1);

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToWantRoute;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);
    event SwapRewardPool(address rewardPool);

    constructor(
        address _rewardPool,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToWantRoute
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = QUICK;
        rewardPool = _rewardPool;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        require(_outputToWantRoute[0] == output, "toDeposit[0] != output");
        require(_outputToWantRoute[_outputToWantRoute.length - 1] == want, "!want");
        outputToWantRoute = _outputToWantRoute;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IDragonsLair(dragonsLair).enter(wantBal);
            uint256 wantDBal = balanceOfWantD();
            IRewardPool(rewardPool).stake(wantDBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();
        uint256 wantDBal = balanceOfWantD();
        uint256 amountD = IDragonsLair(dragonsLair).QUICKForDQUICK(_amount);

        if (wantBal < _amount) {
            IRewardPool(rewardPool).withdraw(amountD.sub(wantDBal));
            IDragonsLair(dragonsLair).leave(amountD.sub(wantDBal));
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin == owner() || paused()) {
            IERC20(want).safeTransfer(vault, wantBal);
        } else {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            IERC20(want).safeTransfer(vault, wantBal.sub(withdrawalFeeAmount));
        }
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
    }

    function harvest() external virtual {
        _harvest();
    }

    function managerHarvest() external onlyManager {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        require(tx.origin == msg.sender || msg.sender == vault, "!contract");
        IRewardPool(rewardPool).getReward();
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees();
            swapRewards();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender);
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
    }

    // swap rewards to {want}
    function swapRewards() internal {
        if (want != output) {
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToWantRoute, address(this), block.timestamp);
        }
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'wantD' this contract holds.
    function balanceOfWantD() public view returns (uint256) {
        return IERC20(dragonsLair).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        uint256 wantDBal = IRewardPool(rewardPool).balanceOf(address(this));
        return IDragonsLair(dragonsLair).dQUICKForQUICK(wantDBal);
    }

    // it calculates how much 'wantD' the strategy has working in the farm.
    function balanceOfPoolD() public view returns (uint256) {
        return IRewardPool(rewardPool).balanceOf(address(this));
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IRewardPool(rewardPool).withdraw(balanceOfPoolD());
        IDragonsLair(dragonsLair).leave(balanceOfWantD());

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit == true) {
            super.setWithdrawalFee(0);
        } else {
            super.setWithdrawalFee(10);
        }
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IRewardPool(rewardPool).withdraw(balanceOfPoolD());
        IDragonsLair(dragonsLair).leave(balanceOfWantD());
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

    function outputToNative() public view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToWant() public view returns (address[] memory) {
        return outputToWantRoute;
    }

    function _giveAllowances() internal {
        IERC20(want).safeApprove(dragonsLair, uint256(-1));
        IERC20(dragonsLair).safeApprove(rewardPool, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(dragonsLair, 0);
        IERC20(dragonsLair).safeApprove(rewardPool, 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

    function swapRewardPool(address _rewardPool, address[] memory _outputToNativeRoute, address[] memory _outputToWantRoute) external onlyOwner {
        require(dragonsLair == IRewardPool(_rewardPool).stakingToken(), "Proposal not valid for this Vault");
        require((_outputToNativeRoute[0] == IRewardPool(_rewardPool).rewardsToken())
            && (_outputToWantRoute[0] == IRewardPool(_rewardPool).rewardsToken()),
            "Proposed output in route is not valid");
        require(_outputToWantRoute[_outputToWantRoute.length - 1] == want, "Proposed want in route is not valid");

        IRewardPool(rewardPool).withdraw(balanceOfPoolD());
        _removeAllowances();

        rewardPool = _rewardPool;
        output = _outputToNativeRoute[0];
        outputToNativeRoute = _outputToNativeRoute;
        outputToWantRoute = _outputToWantRoute;

        _giveAllowances();
        IRewardPool(rewardPool).stake(balanceOfWantD());
        emit SwapRewardPool(rewardPool);
    }
}
