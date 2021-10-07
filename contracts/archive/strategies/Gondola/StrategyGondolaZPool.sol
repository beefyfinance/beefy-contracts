// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IMasterChef.sol";
import "../../interfaces/gondola/IGondolaLP.sol";
import "../../interfaces/gondola/IGondolaSwap.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyGondolaZPool is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wavax  = address(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    address constant public output = address(0xD606199557c8Ab6F4Cc70bD03FaCc96ca576f142);
    address public want;
    address public swapToken;
    address public depositToken;

    // Third party contracts
    address constant public masterchef = address(0x34C8712Cc527a8E6834787Bd9e3AD4F2537B0f50);
    uint256 public poolId;

    // Routes
    address[] public outputToWavaxRoute = [output, wavax];
    address[] public outputToDepositRoute;

    /**
     * @dev Event that is fired each time someone harvests the strat.
     */
    event StratHarvest(address indexed harvester);

    constructor(
        address _want,
        uint256 _poolId,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;
        poolId = _poolId;

        swapToken = IGondolaLP(want).swap();
        depositToken = IGondolaSwap(swapToken).getToken(0);

        if (depositToken == wavax) {
            outputToDepositRoute = [output, wavax];
        } else if (depositToken != output) {
            outputToDepositRoute = [output, wavax, depositToken];
        }

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IMasterChef(masterchef).deposit(poolId, wantBal);
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal < _amount) {
            IMasterChef(masterchef).withdraw(poolId, _amount.sub(wantBal));
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
    function harvest() external whenNotPaused {
        IMasterChef(masterchef).deposit(poolId, 0);
        chargeFees();
        addLiquidity();
        deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees() internal {
        uint256 toWavax = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouter(unirouter).swapExactTokensForTokens(toWavax, 0, outputToWavaxRoute, address(this), now);

        uint256 wavaxBal = IERC20(wavax).balanceOf(address(this));

        uint256 callFeeAmount = wavaxBal.mul(callFee).div(MAX_FEE);
        IERC20(wavax).safeTransfer(msg.sender, callFeeAmount);

        uint256 beefyFeeAmount = wavaxBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wavax).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = wavaxBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wavax).safeTransfer(strategist, strategistFee);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IUniswapRouter(unirouter).swapExactTokensForTokens(outputBal, 0, outputToDepositRoute, address(this), now);

        uint256 depositBal = IERC20(depositToken).balanceOf(address(this));
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = depositBal;
        IGondolaSwap(swapToken).addLiquidity(amounts, 0, now);
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
        (uint256 _amount, ) = IMasterChef(masterchef).userInfo(poolId, address(this));
        return _amount;
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        IMasterChef(masterchef).emergencyWithdraw(poolId);

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        IMasterChef(masterchef).emergencyWithdraw(poolId);
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
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(depositToken).safeApprove(swapToken, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(masterchef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(depositToken).safeApprove(swapToken, 0);
    }
}