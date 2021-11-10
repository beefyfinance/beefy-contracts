// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/common/IUniswapRouter.sol";
import "../../interfaces/lendhub/IComptroller.sol";
import "../../interfaces/venus/IVToken.sol";
import "../Common/StratManager.sol";
import "../Common/FeeManager.sol";


//Lending Strategy 
contract StrategyScreamSlice is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public iToken;

    // Third party contracts
    address constant public comptroller = 0x260E596DAbE3AFc463e75B6CC05d8c46aCAcFB09;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToWantRoute;
    address[] public markets;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;

    /**
     * @dev Variables that can be changed to config profitability and risk:
     * {borrowRate}          - What % of our collateral do we borrow per leverage level.
     * {borrowRateMax}       - A limit on how much we can push borrow risk.
     * {borrowDepth}         - How many levels of leverage do we take.
     * {minLeverage}         - The minimum amount of collateral required to leverage.
     * {BORROW_DEPTH_MAX}    - A limit on how many steps we can leverage.
     * {INTEREST_RATE_MODE}  - The type of borrow debt. Stable: 1, Variable: 2.
     */
    uint256 public borrowRate;
    uint256 public borrowRateMax;
    uint256 public borrowDepth;
    uint256 public minLeverage;
    uint256 constant public BORROW_DEPTH_MAX = 10;

    /**
     * @dev Helps to differentiate borrowed funds that shouldn't be used in functions like 'deposit()'
     * as they're required to deleverage correctly.
     */
    uint256 public reserves;
    uint256 public balanceOfPool;

    /**
     * @dev Events that the contract emits
     */
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event StratRebalance(uint256 _borrowRate, uint256 _borrowDepth);

    constructor(
        uint256 _borrowRate,
        uint256 _borrowRateMax,
        uint256 _borrowDepth,
        uint256 _minLeverage,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToWantRoute,
        address[] memory _markets,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        borrowRate = _borrowRate;
        borrowRateMax = _borrowRateMax;
        borrowDepth = _borrowDepth;
        minLeverage = _minLeverage;

        iToken = _markets[0];
        markets = _markets;
        want = IVToken(iToken).underlying();

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];
        outputToNativeRoute = _outputToNativeRoute;

        require(_outputToWantRoute[0] == output, "outputToWantRoute[0] != output");
        require(_outputToWantRoute[_outputToWantRoute.length - 1] == want, "outputToNativeRoute[last] != want");
        outputToWantRoute = _outputToWantRoute;



        _giveAllowances();

        super.setCallFee(11);

        IComptroller(comptroller).enterMarkets(markets);
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = availableWant();

        if (wantBal > 0) {
            _leverage(wantBal);
            emit Deposit(balanceOf());
        }

    }

    /**
     * @dev Repeatedly supplies and borrows {want} following the configured {borrowRate} and {borrowDepth}
     * @param _amount amount of {want} to leverage
     */
    function _leverage(uint256 _amount) internal {
        if (_amount < minLeverage) { return; }

        for (uint i = 0; i < borrowDepth; i++) {
            IVToken(iToken).mint(_amount);
            _amount = _amount.mul(borrowRate).div(100);
            IVToken(iToken).borrow(_amount);
        }

        reserves = reserves.add(_amount);

        updateBalance();
    }


    /**
     * @dev Incrementally alternates between paying part of the debt and withdrawing part of the supplied
     * collateral. Continues to do this until it repays the entire debt and withdraws all the supplied {want}
     * from the system
     */
    function _deleverage() internal {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        uint256 borrowBal = IVToken(iToken).borrowBalanceCurrent(address(this));

        while (wantBal < borrowBal) {
            IVToken(iToken).repayBorrow(wantBal);

            borrowBal = IVToken(iToken).borrowBalanceCurrent(address(this));
            uint256 targetSupply = borrowBal.mul(100).div(borrowRate);

            uint256 supplyBal = IVToken(iToken).balanceOfUnderlying(address(this));
            IVToken(iToken).redeemUnderlying(supplyBal.sub(targetSupply));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (borrowBal > 0) {
            IVToken(iToken).repayBorrow(uint256(-1));
        }

        uint256 iTokenBal = IERC20(iToken).balanceOf(address(this));
        if(iTokenBal > 0) {
            IVToken(iToken).redeem(iTokenBal);
        }

        reserves = 0;

        updateBalance();
    }

     /**
     * @dev Incrementally alternates between paying a representative part of the debt and withdrawing part of the supplied
     * collateral. Continues to do this until it extracts the required {want} from the system. 1-2% extra is extracted to
     * ensure the withdrawal goes through
     */
    function _deleverageAmount(uint256 _amount) internal {
        uint256 share = _amount.mul(1e18).div(balanceOfPool);

        if (borrowRate == 0) {
            IVToken(iToken).redeemUnderlying(_amount);
        } else {
            uint256 repayAmount = reserves.mul(share).div(1e18);
            reserves = reserves.sub(repayAmount);
            uint256 borrowReserves = IVToken(iToken).borrowBalanceCurrent(address(this)).mul(1e18 - share).div(1e18);
            uint256 supplyReserves = IVToken(iToken).balanceOfUnderlying(address(this)).mul(1e18 - share).div(1e18);

            while (repayAmount < borrowBalSlice(borrowReserves)) {
                IVToken(iToken).repayBorrow(repayAmount);

                uint256 targetSupply = borrowBalSlice(borrowReserves).mul(100).div(borrowRate);
                repayAmount = supplyBalSlice(supplyReserves).sub(targetSupply);

                IVToken(iToken).redeemUnderlying(repayAmount);
            }

            if (borrowBalSlice(borrowReserves) > 0) {
                IVToken(iToken).repayBorrow(borrowBalSlice(borrowReserves));
            }

            if (supplyBalSlice(supplyReserves) > 0) {
                IVToken(iToken).redeemUnderlying(supplyBalSlice(supplyReserves));
            }
        }

        updateBalance();

    }

    /**
     * @dev Extra safety measure that allows us to manually unwind one level. In case we somehow get into
     * as state where the cost of unwinding freezes the system. We can manually unwind a few levels
     * with this function and then 'rebalance()' with new {borrowRate} and {borrowConfig} values.
     * @param _borrowRate configurable borrow rate in case it's required to unwind successfully
     */
    function deleverageOnce(uint _borrowRate) external onlyManager {
        require(_borrowRate <= borrowRateMax, "!safe");

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IVToken(iToken).repayBorrow(wantBal);

        uint256 borrowBal = IVToken(iToken).borrowBalanceCurrent(address(this));
        uint256 targetSupply = borrowBal.mul(100).div(_borrowRate);

        uint256 supplyBal = IVToken(iToken).balanceOfUnderlying(address(this));
        IVToken(iToken).redeemUnderlying(supplyBal.sub(targetSupply));

        wantBal = IERC20(want).balanceOf(address(this));
        reserves = wantBal;

        updateBalance();
    }


    /**
     * @dev Updates the risk profile and rebalances the vault funds accordingly.
     * @param _borrowRate percent to borrow on each leverage level.
     * @param _borrowDepth how many levels to leverage the funds.
     */
    function rebalance(uint256 _borrowRate, uint256 _borrowDepth) external onlyManager {
        require(_borrowRate <= borrowRateMax, "!rate");
        require(_borrowDepth <= BORROW_DEPTH_MAX, "!depth");

        _deleverage();
        borrowRate = _borrowRate;
        borrowDepth = _borrowDepth;

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        _leverage(wantBal);

        StratRebalance(_borrowRate, _borrowDepth);
    }

    function borrowBalSlice(uint256 _borrowReserves) internal returns (uint256) {
        return IVToken(iToken).borrowBalanceCurrent(address(this)).sub(_borrowReserves);
    }

    function supplyBalSlice(uint256 _supplyReserves) internal returns (uint256) {
        return IVToken(iToken).balanceOfUnderlying(address(this)).sub(_supplyReserves);
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
        updateBalance();
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
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        if (IComptroller(comptroller).pendingComptrollerImplementation() == address(0)) {
            uint256 beforeBal = availableWant();
            IComptroller(comptroller).claimComp(address(this), markets);
            uint256 outputBal = IERC20(output).balanceOf(address(this));
            if (outputBal > 0) {
                chargeFees(callFeeRecipient);
                swapRewards();
                uint256 wantHarvested = availableWant().sub(beforeBal);
                deposit();

                lastHarvest = block.timestamp;
                emit StratHarvest(msg.sender, wantHarvested, balanceOf());
            }
        } else {
            panic();
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal {
        uint256 toNative = IERC20(output).balanceOf(address(this)).mul(45).div(1000);
        IUniswapRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
    }

    // swap rewards to {want}
    function swapRewards() internal {
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        IUniswapRouter(unirouter).swapExactTokensForTokens(outputBal, 0, outputToWantRoute, address(this), now);
    }

    /**
     * @dev Withdraws funds and sends them back to the vault. It deleverages from venus first,
     * and then deposits again after the withdraw to make sure it mantains the desired ratio.
     * @param _amount How much {want} to withdraw.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = availableWant();

        if (wantBal < _amount) {
            _deleverageAmount(_amount.sub(wantBal));
            wantBal = availableWant();
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

        if (!paused()) {
            _leverage(availableWant());
        }
    }

    /**
     * @dev Required for various functions that need to deduct {reserves} from total {want}.
     * @return how much {want} the contract holds without reserves
     */
    function availableWant() public view returns (uint256) {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        return wantBal.sub(reserves);
    }

    // return supply and borrow balance
    function updateBalance() public {
        uint256 supplyBal = IVToken(iToken).balanceOfUnderlying(address(this));
        uint256 borrowBal = IVToken(iToken).borrowBalanceCurrent(address(this));
        balanceOfPool = supplyBal.sub(borrowBal);
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant().add(balanceOfPool);
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
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

        _deleverage();

        uint256 wantBal = IERC20(want).balanceOf(address(this));
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        _deleverage();
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
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(iToken, 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

     function outputToNative() external view returns(address[] memory) {
        return outputToNativeRoute;
    }

    function outputToWant() external view returns(address[] memory) {
        return outputToWantRoute;
    }
}