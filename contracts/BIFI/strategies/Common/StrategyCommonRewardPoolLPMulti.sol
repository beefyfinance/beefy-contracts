// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IRewardPool.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";
import "./StrategyCommonRewardPoolLP.sol";

contract StrategyCommonRewardPoolLPMulti is StrategyCommonRewardPoolLP {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public secondOutput;
    address[] public secondOutputToOutputRoute;

    constructor(
        address _want,
        address _rewardPool,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route,
        address[] memory _secondOutputToOutputRoute
    ) StrategyCommonRewardPoolLP(
    _want,
    _rewardPool,
    _vault,
    _unirouter,
    _keeper,
    _strategist,
    _beefyFeeRecipient,
    _outputToNativeRoute,
    _outputToLp0Route,
    _outputToLp1Route
    ) public {
        secondOutput = _secondOutputToOutputRoute[0];
        secondOutputToOutputRoute = _secondOutputToOutputRoute;

        _giveSecondOutputAllowances();
    }

    // compounds earnings and charges performance fee
    function harvest() override external whenNotPaused onlyEOA {
        IRewardPool(rewardPool).getReward();
        chargeFees();
        super.addLiquidity();
        super.deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees() override internal {
        uint256 toOutput = IERC20(secondOutput).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toOutput, 0, secondOutputToOutputRoute, address(this), now);

        super.chargeFees();
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() override public onlyManager {
        pause();
        IRewardPool(rewardPool).withdraw(balanceOfPool());
    }

    function pause() override public onlyManager {
        super._pause();

        super._removeAllowances();
        _removeSecondOutputAllowances();
    }

    function unpause() override external onlyManager {
        super._unpause();

        super._giveAllowances();
        _giveSecondOutputAllowances();

        super.deposit();
    }

    function _giveSecondOutputAllowances() internal {
        IERC20(secondOutput).safeApprove(unirouter, uint256(-1));
    }

    function _removeSecondOutputAllowances() internal {
        IERC20(secondOutput).safeApprove(unirouter, 0);
    }
}
