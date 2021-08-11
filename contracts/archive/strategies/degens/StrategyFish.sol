// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/polycat/IMasterChefCat.sol";
import "../Common/FeeManager.sol";
import "../Common/StratManager.sol";

contract StrategyFish is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wrapped = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address constant public want = address(0x3a3Df212b7AA91Aa0402B9035b098891d276572B);

    // Third party contracts
    address constant public masterchef = address(0x8CFD1B9B7478E7B0422916B72d1DB6A9D513D734);
    address constant public referrer = address(0x0000000000000000000000000000000000000000);
    uint256 constant public poolId = 1;

    // Routes
    address[] public wantToWrappedRoute = [want, wrapped];

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    constructor(
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChefCat(masterchef).deposit(poolId, wantBal, referrer);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChefCat(masterchef).withdraw(poolId, _amount.sub(wantBal));
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
        harvest();
    }

    // compounds earnings and charges performance fee
    function harvest() public whenNotPaused {
        require(tx.origin == msg.sender || msg.sender == vault, "!contract");
        IMasterChefCat(masterchef).deposit(poolId, 0, referrer);
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        if (wantBal > 0) {
            chargeFees();
            deposit();
            emit StratHarvest(msg.sender);
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 toWrapped = IERC20(want).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouter(unirouter).swapExactTokensForTokens(toWrapped, 0, wantToWrappedRoute, address(this), now);

        uint256 wrappedBal = IERC20(wrapped).balanceOf(address(this));

        uint256 callFeeAmount = wrappedBal.mul(callFee).div(MAX_FEE);
        IERC20(wrapped).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = wrappedBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wrapped).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = wrappedBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wrapped).safeTransfer(strategist, strategistFee);
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
        (uint256 _amount, ) = IMasterChefCat(masterchef).userInfo(poolId, address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMasterChefCat(masterchef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMasterChefCat(masterchef).emergencyWithdraw(poolId);
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
        IERC20(want).safeApprove(masterchef, uint256(-1));
        IERC20(want).safeApprove(unirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(want).safeApprove(unirouter, 0);
    }
}