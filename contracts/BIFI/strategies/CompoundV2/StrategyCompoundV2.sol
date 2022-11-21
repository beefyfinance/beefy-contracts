// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../../interfaces/common/IComptroller.sol";
import "../../interfaces/common/IVToken.sol";
import "../Common/StratFeeManager.sol";
import "../../utils/GasFeeThrottler.sol";


//Lending Strategy 
contract StrategyCompoundV2 is StratFeeManager, GasFeeThrottler {
    using SafeERC20 for IERC20;

    // Tokens used
    address public native;
    address public output;
    address public want;
    address public iToken;

    // Third party contracts
    address public comptroller;

    // Routes
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
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);

    constructor(
        uint256 _borrowRate,
        uint256 _borrowRateMax,
        uint256 _borrowDepth,
        uint256 _minLeverage,
        address[] memory _markets,
        address _comptroller,
        CommonAddresses memory _commonAddresses
    ) StratFeeManager(_commonAddresses) {
        borrowRate = _borrowRate;
        borrowRateMax = _borrowRateMax;
        borrowDepth = _borrowDepth;
        minLeverage = _minLeverage;

        iToken = _markets[0];
        markets = _markets;
        comptroller = _comptroller;
        want = IVToken(iToken).underlying();
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

        for (uint i; i < borrowDepth;) {
            IVToken(iToken).mint(_amount);
            _amount = _amount * borrowRate / 100;
            IVToken(iToken).borrow(_amount);
            unchecked { ++i; }
        }

        reserves += _amount;

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
            uint256 targetSupply = borrowBal * 100 / borrowRate;

            uint256 supplyBal = IVToken(iToken).balanceOfUnderlying(address(this));
            uint error = IVToken(iToken).redeemUnderlying(supplyBal - targetSupply);
            require(error == 0, "Error while trying to redeem");

            wantBal = IERC20(want).balanceOf(address(this));
        }

        IVToken(iToken).repayBorrow(type(uint256).max);

        uint256 iTokenBal = IERC20(iToken).balanceOf(address(this));
        IVToken(iToken).redeem(iTokenBal);

        reserves = 0;

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
        uint256 targetSupply = borrowBal * 100 / _borrowRate;

        uint256 supplyBal = IVToken(iToken).balanceOfUnderlying(address(this));
        uint error = IVToken(iToken).redeemUnderlying(supplyBal - targetSupply);
        require(error == 0, "Error while trying to redeem");

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

        emit StratRebalance(_borrowRate, _borrowDepth);
    }

    function beforeDeposit() external override {
        if (harvestOnDeposit) {
            require(msg.sender == vault, "!vault");
            _harvest(tx.origin);
        }
        updateBalance();
    }

    function harvest() external gasThrottle virtual {
        _harvest(tx.origin);
    }

    function harvest(address callFeeRecipient) external gasThrottle virtual {
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
                uint256 wantHarvested = availableWant() - beforeBal;
                deposit();

                lastHarvest = block.timestamp;
                emit StratHarvest(msg.sender, wantHarvested, balanceOf());
            }
        } else {
            panic();
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient) internal virtual {}

    // swap rewards to {want}
    function swapRewards() internal virtual {}

    /**
     * @dev Withdraws funds and sends them back to the vault. It deleverages from market first,
     * and then deposits again after the withdraw to make sure it mantains the desired ratio.
     * @param _amount How much {want} to withdraw.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = availableWant();

        if (wantBal < _amount) {
            _deleverage();
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (wantBal > _amount) {
            wantBal = _amount;
        }

        if (tx.origin != owner() && !paused()) {
            uint256 withdrawalFeeAmount = wantBal * withdrawalFee / WITHDRAWAL_MAX;
            wantBal = wantBal - withdrawalFeeAmount;
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
        return wantBal - reserves;
    }

    // return supply and borrow balance
    function updateBalance() public {
        uint256 supplyBal = IVToken(iToken).balanceOfUnderlying(address(this));
        uint256 borrowBal = IVToken(iToken).borrowBalanceCurrent(address(this));
        balanceOfPool = supplyBal - borrowBal;
    }


    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool;
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
    function callReward() public virtual returns (uint256) {}

    function setHarvestOnDeposit(bool _harvestOnDeposit) external onlyManager {
        harvestOnDeposit = _harvestOnDeposit;

        if (harvestOnDeposit) {
            super.setWithdrawalFee(0);
        } else {
            super.setWithdrawalFee(10);
        }
    }

    function setShouldGasThrottle(bool _shouldGasThrottle) external onlyManager {
        shouldGasThrottle = _shouldGasThrottle;
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
        IERC20(want).safeApprove(iToken, type(uint256).max);
        IERC20(output).safeApprove(unirouter, type(uint256).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(iToken, 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

    function outputToNative() external view virtual returns (address[] memory) {}

    function outputToWant() external view virtual returns (address[] memory) {}
}