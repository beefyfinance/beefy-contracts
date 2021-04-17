// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "../strategies/Common/BeefyStrategy"

abstract contract FeeManager is BeefyStrategy {
    uint constant public TREASURY_FEE   = 112;
    uint constant public STRATEGIST_FEE = 112;
    uint constant public MAX_FEE = 1000;
    uint constant public MAX_CALL_FEE = 111;

    uint constant public WITHDRAWAL_FEE = 10;
    uint constant public WITHDRAWAL_MAX = 10000;

    uint public callFee = 111;
    uint public rewardsFee = MAX_FEE - TREASURY_FEE - STRATEGIST_FEE - callFee;

    uint constant public CHARGED = 45;
    uint constant public MAX = 10000;

    function chargeFees() internal {
        uint256 toWbnb = IERC20(output).balanceOf(address(this)).mul(CHARGED).div(MAX);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toWbnb, 0, outputToWbnbRoute, address(this), now.add(600));

        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));

        uint256 callFee = wbnbBal.mul(CALL_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(msg.sender, callFee);

        uint256 treasuryHalf = wbnbBal.mul(TREASURY_FEE).div(MAX_FEE).div(2);
        IERC20(wbnb).safeTransfer(treasury, treasuryHalf);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(treasuryHalf, 0, wbnbToBifiRoute, treasury, now.add(600));

        uint256 rewardsFee = wbnbBal.mul(REWARDS_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(rewards, rewardsFee);

        uint256 strategistFee = wbnbBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
    }

    function setCallFee(uint256 _fee) external onlyManager {
        require(_fee <= MAX_CALL_FEE, "!cap");
        
        callFee = _fee;
        rewardsFee = MAX_FEE - TREASURY_FEE - STRATEGIST_FEE - callFee;
    }

    function _transferWithWithdrawFee() internal {
        if (tx.origin == owner() || paused()) {
            IERC20(want).safeTransfer(vault, want);
        } else {
            uint256 withdrawalFee = want.mul(WITHDRAWAL_FEE).div(WITHDRAWAL_MAX);
            IERC20(want).safeTransfer(vault, want.sub(withdrawalFee));
        }
    }
}