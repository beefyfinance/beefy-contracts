// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IUniswapV2Pair.sol";
import "../../interfaces/common/IWrappedNative.sol";
import "../../interfaces/solar/ISolarChef.sol";
import "../../interfaces/common/IxWant.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";

contract StrategyStella is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public xWant;

    // Third party contracts
    address public chef;
    uint256 public poolId;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    // Routes
    address[] public outputToNativeRoute;
    address[][] public rewardToOutputRoute;

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address _xWant,
        uint256 _poolId,
        address _chef,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        xWant = _xWant;
        want = IxWant(xWant).stella();
        poolId = _poolId;
        chef = _chef;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = IERC20(want).balanceOf(address(this));

        if (wantBal > 0) {
            IxWant(xWant).enter(wantBal);
            uint256 xWantBal = balanceOfXWant();
            ISolarChef(chef).deposit(poolId, xWantBal);
            emit Deposit(balanceOf());
        }
    }

    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();
        uint256 xWantBal = balanceOfXWant();
        uint256 xAmount = stellaToXStella(_amount);

        if (wantBal < _amount) {
            ISolarChef(chef).withdraw(poolId, xAmount.sub(xWantBal));
            IxWant(xWant).leave(xAmount.sub(xWantBal));
            wantBal = balanceOfWant();
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal.mul(withdrawalFee).div(WITHDRAWAL_MAX);
            wantBal = wantBal.sub(withdrawalFeeAmount);
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

    function harvest() external virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external virtual {
        _harvest(callFeeRecipient);
    }

    function managerHarvest() external onlyManager {
        _harvest(tx.origin);
    }

    // compounds earnings and charges performance fee
    function _harvest(address callFeeRecipient) internal {
        ISolarChef(chef).deposit(poolId, 0);
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            addLiquidity();
            uint256 wantHarvested = stellaToXStella(balanceOfXWant());
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                if (rewardToOutputRoute[i][0] == native) {
                    uint256 nativeBal = address(this).balance;
                    if (nativeBal > 0) {
                        IWrappedNative(native).deposit{value: nativeBal}();
                    }
                }
                uint256 rewardBal = IERC20(rewardToOutputRoute[i][0]).balanceOf(address(this));
                if (rewardBal > 0) {
                    IUniswapRouterETH(unirouter).swapExactTokensForTokens(rewardBal, 0, rewardToOutputRoute[i], address(this), now);
                }
            }
        }

        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouterETH(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity() internal {
        uint256 outputBal = balanceOfXWant();
        IxWant(xWant).enter(outputBal);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfXWant() public view returns (uint256) {
        return IERC20(xWant).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfXWantInPool() public view returns (uint256) {
        (uint256 _amount,,,) = ISolarChef(chef).userInfo(poolId, address(this));
        return _amount;
    }

    function balanceOfPool() public view returns (uint256) {
        return xStellaToStella(balanceOfXWantInPool());
    }

    // Calc Stella to xStella Rate 
    function stellaToXStella (uint256 _amount) public view returns (uint256) {
        return _amount.mul(IxWant(xWant).totalSupply()).div(IERC20(want).balanceOf(xWant));
    }

     // Calc Stella to xStella Rate 
    function xStellaToStella (uint256 _amount) public view returns (uint256) {
        return _amount.mul(IERC20(want).balanceOf(xWant)).div(IxWant(xWant).totalSupply());
    }

    function rewardsAvailable() public view returns (address[] memory, uint256[] memory) {
        (address[] memory addresses,,,uint256[] memory amounts) = ISolarChef(chef).pendingTokens(poolId, address(this));
        return (addresses, amounts);
    }

    function callReward() public view returns (uint256) {
        (address[] memory rewardAdd, uint256[] memory rewardBal) = rewardsAvailable();
        uint256 nativeBal;
        try IUniswapRouterETH(unirouter).getAmountsOut(rewardBal[0], outputToNativeRoute)
        returns (uint256[] memory amountOut) {
            nativeBal = amountOut[amountOut.length - 1];
        } catch {}

        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                for (uint j = 1; j < rewardAdd.length; j++) {
                    if (rewardAdd[j] == rewardToOutputRoute[i][0]) {
                        try IUniswapRouterETH(unirouter).getAmountsOut(rewardBal[j], rewardToOutputRoute[i])
                        returns (uint256[] memory initialAmountOut) {
                            uint256 outputBal = initialAmountOut[initialAmountOut.length - 1];
                            try IUniswapRouterETH(unirouter).getAmountsOut(outputBal, outputToNativeRoute)
                            returns (uint256[] memory finalAmountOut) {
                                nativeBal = nativeBal.add(finalAmountOut[finalAmountOut.length - 1]);
                            } catch {}
                        } catch {}
                    }
                }
            }
        }

        return nativeBal.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            setWithdrawalFee(0);
        } else {
            setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        ISolarChef(chef).emergencyWithdraw(poolId);
        IxWant(xWant).leave(balanceOfXWant());

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        pause();
        ISolarChef(chef).emergencyWithdraw(poolId);
        IxWant(xWant).leave(balanceOfXWant());
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
        IERC20(xWant).safeApprove(chef, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(want).safeApprove(xWant, uint256(-1));

        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                IERC20(rewardToOutputRoute[i][0]).safeApprove(unirouter, 0);
                IERC20(rewardToOutputRoute[i][0]).safeApprove(unirouter, uint256(-1));
            }
        }
    }

    function _removeAllowances() internal {
        IERC20(xWant).safeApprove(chef, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(want).safeApprove(xWant, 0);

        if (rewardToOutputRoute.length != 0) {
            for (uint i; i < rewardToOutputRoute.length; i++) {
                IERC20(rewardToOutputRoute[i][0]).safeApprove(unirouter, 0);
            }
        }
    }

    function addRewardRoute(address[] memory _rewardToOutputRoute) external onlyOwner {
        IERC20(_rewardToOutputRoute[0]).safeApprove(unirouter, 0);
        IERC20(_rewardToOutputRoute[0]).safeApprove(unirouter, uint256(-1));
        rewardToOutputRoute.push(_rewardToOutputRoute);
    }

    function removeLastRewardRoute() external onlyManager {
        address reward = rewardToOutputRoute[rewardToOutputRoute.length - 1][0];
        IERC20(reward).safeApprove(unirouter, 0);
    
        rewardToOutputRoute.pop();
    }

    function outputToNative() external view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function rewardToOutput(uint256 _i) external view returns (address[] memory) {
        return rewardToOutputRoute[_i];
    }
     
    receive () external payable {}
}
