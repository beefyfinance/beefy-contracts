// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMultiFeeDistribution.sol";
import "../../interfaces/curve/ICurveSwap.sol";
import "../../interfaces/ellipsis/ILpStaker.sol";
import "../../interfaces/ellipsis/IRewardToken.sol";
import "../../utils/GasThrottler.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

interface ISwap {
    function exchange_underlying(int128 i, int128 j, uint256 _dx, uint256 _min_dy) external returns (uint256);
}

contract StrategyEllipsisUsdn is StratManager, FeeManager, GasThrottler {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public want = address(0x8339156534e2d7354Eed097A6FB4A5820d8d0d27);
    address constant public rewardToken = address(0x03ab98f5dc94996F8C33E15cD4468794d12d41f9); // USDN
    address constant public busd = address(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    address constant public wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
    address constant public eps  = address(0xA7f552078dcC247C2684336020c03648500C6d9F);
    address constant public depositToken = busd;

    // Third party contracts
    address constant public stakingPool     = address(0xcce949De564fE60e7f96C85e55177F8B9E4CF61b);
    address constant public feeDistribution = address(0x4076CC26EFeE47825917D0feC3A79d0bB9a6bB5c);
    address constant public swap = address(0x2f8E25C21A17BD9D0C337e1b409e73bc959B41BE);
    address constant public pool = address(0xDd4DA48b4BE0f7F19411Fbda7cc3f90F173FAE88);
    uint constant public poolId = 8;
    uint constant public poolSize = 4;
    uint constant public depositIndex = 1;
    int128 constant public swapFromIndex = 0;
    int128 constant public swapToIndex = 1;

    // Routes
    address[] public epsToWbnbRoute  = [eps, wbnb];
    address[] public busdWbnbRoute = [busd, wbnb];
    address[] public wbnbToDepositRoute = [wbnb, busd];

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
            ILpStaker(stakingPool).deposit(poolId, wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            ILpStaker(stakingPool).withdraw(poolId, _amount.sub(wantBal));
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

    // compounds earnings and charges performance fee
    function harvest() external whenNotPaused gasThrottle {
        uint256[] memory pids = new uint256[](1);
        pids[0] = poolId;
        ILpStaker(stakingPool).claim(pids);
        IMultiFeeDistribution(feeDistribution).exit();

        IRewardToken(want).getReward();
        convertAdditionalRewards();

        chargeFees();
        swapRewards();
        deposit();

        emit StratHarvest(msg.sender);
    }

    // swap additional rewards to wbnb
    function convertAdditionalRewards() internal {
        uint256 rewardBal = IERC20(rewardToken).balanceOf(address(this));
        if (rewardBal > 0) {
            ISwap(swap).exchange_underlying(swapFromIndex, swapToIndex, rewardBal, 0);
        }

        uint256 busdBal = IERC20(busd).balanceOf(address(this));
        if (busdBal > 0) {
            IUniswapRouter(unirouter).swapExactTokensForTokens(busdBal, 0, busdWbnbRoute, address(this), block.timestamp);
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 epsBal = IERC20(eps).balanceOf(address(this));
        if (epsBal > 0) {
            IUniswapRouter(unirouter).swapExactTokensForTokens(epsBal, 0, epsToWbnbRoute, address(this), block.timestamp);
        }

        uint256 wbnbFeeBal = IERC20(wbnb).balanceOf(address(this)).mul(45).div(1000);

        uint256 callFeeAmount = wbnbFeeBal.mul(callFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = wbnbFeeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = wbnbFeeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wbnb).safeTransfer(strategist, strategistFee);
    }

    // swaps {wbnb} for {depositToken} and adds to Eps LP.
    function swapRewards() internal {
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));
        IUniswapRouter(unirouter).swapExactTokensForTokens(wbnbBal, 0, wbnbToDepositRoute, address(this), block.timestamp);

        uint256 depositBal = IERC20(depositToken).balanceOf(address(this));

        if (poolSize == 2) {
            uint256[2] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap2(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 3) {
            uint256[3] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap3(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 4) {
            uint256[4] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap4(pool).add_liquidity(amounts, 0);
        } else if (poolSize == 5) {
            uint256[5] memory amounts;
            amounts[depositIndex] = depositBal;
            ICurveSwap5(pool).add_liquidity(amounts, 0);
        }
    }

    // calculate the total underlying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = ILpStaker(stakingPool).userInfo(poolId, address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        ILpStaker(stakingPool).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ILpStaker(stakingPool).emergencyWithdraw(poolId);
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
        IERC20(want).safeApprove(stakingPool, type(uint).max);
        IERC20(eps).safeApprove(unirouter, type(uint).max);
        IERC20(wbnb).safeApprove(unirouter, type(uint).max);
        IERC20(busd).safeApprove(unirouter, type(uint).max);
        IERC20(depositToken).safeApprove(pool, type(uint).max);
        if (rewardToken != address(0)) {
            IERC20(rewardToken).safeApprove(swap, type(uint).max);
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(stakingPool, 0);
        IERC20(eps).safeApprove(unirouter, 0);
        IERC20(wbnb).safeApprove(unirouter, 0);
        IERC20(busd).safeApprove(unirouter, 0);
        IERC20(depositToken).safeApprove(pool, 0);
        if (rewardToken != address(0)) {
            IERC20(rewardToken).safeApprove(swap, 0);
        }
    }
}