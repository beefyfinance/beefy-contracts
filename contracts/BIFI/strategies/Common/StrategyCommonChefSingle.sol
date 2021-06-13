// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMasterChef.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

import "./StrategyCommonChefBase.sol";

contract StrategyCommonChefSingle is StrategyCommonChefBase {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Routes
    address[] public outputToWantRoute;

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToWantRoute
    ) StrategyCommonChefBase(
        _want,
        _poolId,
        _chef,
        _vault,
        _unirouter,
        _keeper,
        _strategist,
        _beefyFeeRecipient,
        _outputToNativeRoute
    ) {
        outputToWantRoute = _outputToWantRoute;
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function swapRewardForWant() internal override {
        uint256 rewardBal = IERC20(output).balanceOf(address(this));
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(rewardBal, 0, outputToWantRoute, address(this), block.timestamp);
    }
}
