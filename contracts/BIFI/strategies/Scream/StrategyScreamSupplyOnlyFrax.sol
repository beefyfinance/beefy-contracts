// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/common/IComptroller.sol";
import "../../interfaces/common/IVToken.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";


//Lending Strategy 
contract StrategyScreamSupplyOnlyFrax is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public iToken;
    address public secondUnirouter;

    // Third party contracts
    address constant public comptroller = 0x260E596DAbE3AFc463e75B6CC05d8c46aCAcFB09;

    // Routes
    address[] public outputToNativeRoute;
    address[] public nativeToWantRoute;
    address[] public markets;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    uint256 public balanceOfPool;

    /**
     * @dev Events that the contract emits
     */
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        address[] memory _markets,
        address[] memory _outputToNativeRoute,
        address[] memory _nativeToWantRoute,
        address _secondUnirouter,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        markets = _markets;
        iToken = _markets[0];
        want = IVToken(iToken).underlying();
        secondUnirouter = _secondUnirouter;

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        nativeToWantRoute = _nativeToWantRoute;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            IVToken(iToken).mint(wantBal);
            emit Deposit(balanceOf());
        }
        
        updateBalance();
    }

    /**
     * @dev Withdraws funds and sends them back to the vault. It deleverages first,
     * and then deposits again after the withdraw to make sure it mantains the desired ratio.
     * @param _amount How much {want} to withdraw.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();

        if (wantBal < _amount) {
            IVToken(iToken).redeemUnderlying(_amount.sub(wantBal));
            require(balanceOfWant() >= _amount, "Want Balance Less than Requested");
            updateBalance();
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

    function withdrawFromScream() external onlyManager { 
        // Withdraw what we can from Scream 
        updateBalance();
        uint256 wantBal = IERC20(want).balanceOf(iToken);
        if (balanceOfPool > wantBal) {
            IVToken(iToken).redeemUnderlying(wantBal);
        } else { 
            uint256 iTokenBal = IERC20(iToken).balanceOf(address(this));
            IVToken(iToken).redeem(iTokenBal);
        }
        updateBalance();
    }

    function withdrawPartialFromScream(uint256 _amountUnderlying) external onlyManager { 
        // Withdraw what we can from Scream 
        updateBalance();
        require(balanceOfPool >= _amountUnderlying, "more than our Scream balance");
        uint256 wantBal = IERC20(want).balanceOf(iToken);
        require(wantBal >= _amountUnderlying, "not enough in Scream");
         
        IVToken(iToken).redeemUnderlying(_amountUnderlying);
        updateBalance();
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest();
        }
        updateBalance();
    }

    function harvest() external virtual {
        _harvest();
    }

    function managerHarvest() external onlyManager {
        _harvest();
    }

    // compounds earnings and charges performance fee
    function _harvest() internal whenNotPaused {
        if (IComptroller(comptroller).pendingComptrollerImplementation() == address(0)) {
            uint256 beforeBal = balanceOfWant();
            IComptroller(comptroller).claimComp(address(this), markets);
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            if (outputBal > 0) {
                chargeFees();
                swapRewards();
                uint256 wantHarvested = balanceOfWant().sub(beforeBal);
                deposit();

                lastHarvest = block.timestamp;
                emit StratHarvest(msg.sender, wantHarvested, balanceOf());
            }
        } else {
            panic();
        }
    }

    // performance fees
    function chargeFees() internal {
        uint256 toNative = IERC20(output).balanceOf(address(this));
        IUniswapRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this)).mul(45).div(1000);

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);
        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    // swap rewards to {want}
    function swapRewards() internal {
        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        IUniswapRouter(secondUnirouter).swapExactTokensForTokens(nativeBal, 0, nativeToWantRoute, address(this), now);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool);
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // return supply balance
    function updateBalance() public {
        balanceOfPool = IVToken(iToken).balanceOfUnderlying(address(this));
    }

    // returns rewards unharvested
    function rewardsAvailable() public returns (uint256) {
        IComptroller(comptroller).claimComp(address(this), markets);
        return IERC20(output).balanceOf(address(this));
    }

    // native reward amount for calling harvest
    function callReward() public returns (uint256) {
        uint256 outputBal = rewardsAvailable();
        uint256 nativeOut;
        if (outputBal > 0) {
            try IUniswapRouter(unirouter).getAmountsOut(outputBal, outputToNativeRoute)
                returns (uint256[] memory amountOut)
            {
                nativeOut = amountOut[amountOut.length -1];
            }
            catch {}
        }

        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
    }

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit == true) {
            super.setWithdrawalFee(0);
        } else {
            super.setWithdrawalFee(10);
        }
    }

    // called as part of strat migration. Sends all the available funds back to the vault.
    function retireStrat() external {
        require(msg.sender == vault, "!vault");

        uint256 iTokenBal = IERC20(iToken).balanceOf(address(this));
        IVToken(iToken).redeem(iTokenBal);
        updateBalance();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        uint256 iTokenBal = IERC20(iToken).balanceOf(address(this));
        IVToken(iToken).redeem(iTokenBal);
        updateBalance();
        pause();
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
        IERC20(want).safeApprove(iToken, uint256(-1));
        IERC20(output).safeApprove(unirouter, uint256(-1));
        IERC20(native).safeApprove(secondUnirouter, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(iToken, 0);
        IERC20(output).safeApprove(unirouter, 0);
        IERC20(native).safeApprove(secondUnirouter, 0);
    }

     function outputToNative() external view returns(address[] memory) {
        return outputToNativeRoute;
    }

    function nativeToWant() external view returns(address[] memory) {
        return nativeToWantRoute;
    }
}