// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/alpaca/IFairLaunch.sol";
import "../../interfaces/alpaca/IAlpacaVault.sol";
import "../../utils/GasThrottler.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyAlpacaVault is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public output;
    address public native;
    address public want;
    address public wantToken;

    // Third party contracts
    address public chef;
    uint256 public poolId;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToWantTokenRoute;

    bool public harvestOnDeposit = true;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToWantTokenRoute,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        wantToken = IAlpacaVault(want).token();
        poolId = _poolId;
        chef = _chef;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        require(_outputToWantTokenRoute[0] == output, "toDeposit[0] != alpaca");
        require(_outputToWantTokenRoute[_outputToWantTokenRoute.length - 1] == wantToken, "!wantToken");
        outputToWantTokenRoute = _outputToWantTokenRoute;

        _giveAllowances();
        setWithdrawalFee(0);
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IFairLaunch(chef).deposit(address(this), poolId, wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IFairLaunch(chef).withdraw(address(this), poolId, _amount.sub(wantBal));
            wantBal = IERC20(want).balanceOf(address(this));
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

    function harvest() external virtual gasThrottle {
        _harvest();
    }

    function managerHarvest() external onlyManager {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        if (balanceOfPool() > 0) {
            IFairLaunch(chef).harvest(poolId);
            chargeFees();
            addLiquidity();
            deposit();

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

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        if (outputToWantTokenRoute.length > 1) {
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            IUniswapRouterETH(unirouter).swapExactTokensForTokens(outputBal, 0, outputToWantTokenRoute, address(this), now);
        }

        uint256 wantTokenBal = IERC20(wantToken).balanceOf(address(this));
        IAlpacaVault(want).deposit(wantTokenBal);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = IFairLaunch(chef).userInfo(poolId, address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IFairLaunch(chef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IFairLaunch(chef).emergencyWithdraw(poolId);
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
        IERC20(want).safeApprove(chef, uint(-1));
        IERC20(output).safeApprove(unirouter, uint(-1));
        IERC20(wantToken).safeApprove(want, uint(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(wantToken).safeApprove(want, 0);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;
    }

    function outputToNative() public view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function outputToWant() public view returns (address[] memory) {
        return outputToWantTokenRoute;
    }
}
