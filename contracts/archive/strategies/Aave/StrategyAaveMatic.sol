// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/aave/IDataProvider.sol";
import "../../interfaces/aave/IIncentivesController.sol";
import "../../interfaces/aave/ILendingPool.sol";
import "../../interfaces/common/IUniswapRouterETH.sol";
import "../Common/FeeManager.sol";
import "../Common/StratManager.sol";

contract StrategyAaveMatic is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address constant public wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address constant public want = wmatic;
    address public aToken;
    address public varDebtToken;

    // Third party contracts
    address constant public dataProvider = address(0x7551b5D2763519d4e37e8B81929D336De671d46d);
    address constant public lendingPool = address(0x8dFf5E27EA6b7AC08EbFdf9eB090F32ee9a30fcf);
    address constant public incentivesController = address(0x357D51124f59836DeD84c8a1730D72B749d8BC23);

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
    uint256 constant public INTEREST_RATE_MODE = 2;

    /**
     * @dev Helps to differentiate borrowed funds that shouldn't be used in functions like 'deposit()'
     * as they're required to deleverage correctly.  
     */
    uint256 public reserves = 0;

    /**
     * @dev Events that the contract emits
     */
    event StratHarvest(address indexed harvester);
    event StratRebalance(uint256 _borrowRate, uint256 _borrowDepth);

    constructor(
        uint256 _borrowRate,
        uint256 _borrowRateMax,
        uint256 _borrowDepth,
        uint256 _minLeverage,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        (aToken,,varDebtToken) = IDataProvider(dataProvider).getReserveTokensAddresses(want);

        borrowRate = _borrowRate;
        borrowRateMax = _borrowRateMax;
        borrowDepth = _borrowDepth;
        minLeverage = _minLeverage;

        _giveAllowances();
    }

    // puts the funds to work
    function deposit() public whenNotPaused {
        uint256 wantBal = availableWant();

        if (wantBal > 0) {
            _leverage(wantBal);
        }
    }

    /**
     * @dev Repeatedly supplies and borrows {want} following the configured {borrowRate} and {borrowDepth}
     * @param _amount amount of {want} to leverage
     */
    function _leverage(uint256 _amount) internal {
        if (_amount < minLeverage) { return; }

        for (uint i = 0; i < borrowDepth; i++) {
            ILendingPool(lendingPool).deposit(want, _amount, address(this), 0);
            _amount = _amount.mul(borrowRate).div(100);
            ILendingPool(lendingPool).borrow(want, _amount, INTEREST_RATE_MODE, 0, address(this));
        }

        reserves = reserves.add(_amount);
    }


    /**
     * @dev Incrementally alternates between paying part of the debt and withdrawing part of the supplied
     * collateral. Continues to do this until it repays the entire debt and withdraws all the supplied {want}
     * from the system
     */
    function _deleverage() internal {
        uint256 wantBal = IERC20(want).balanceOf(address(this));
        (uint256 supplyBal, uint256 borrowBal) = userReserves();

        while (wantBal < borrowBal) {
            ILendingPool(lendingPool).repay(want, wantBal, INTEREST_RATE_MODE, address(this));

            (supplyBal, borrowBal) = userReserves();
            uint256 targetSupply = borrowBal.mul(100).div(borrowRate);

            ILendingPool(lendingPool).withdraw(want, supplyBal.sub(targetSupply), address(this));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        ILendingPool(lendingPool).repay(want, uint256(-1), INTEREST_RATE_MODE, address(this));
        ILendingPool(lendingPool).withdraw(want, type(uint).max, address(this));

        reserves = 0;
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
        ILendingPool(lendingPool).repay(want, wantBal, INTEREST_RATE_MODE, address(this));

        (uint256 supplyBal, uint256 borrowBal) = userReserves();
        uint256 targetSupply = borrowBal.mul(100).div(_borrowRate);

        ILendingPool(lendingPool).withdraw(want, supplyBal.sub(targetSupply), address(this));

        wantBal = IERC20(want).balanceOf(address(this));
        reserves = wantBal;
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

    // compounds earnings and charges performance fee
    function harvest() external whenNotPaused {
        uint _before = balanceOfWant();

        address[] memory assets = new address[](2);
        assets[0] = aToken;
        assets[1] = varDebtToken;
        IIncentivesController(incentivesController).claimRewards(assets, type(uint).max, address(this));

        uint _after = balanceOfWant();
        uint harvestedBal = _after.sub(_before);

        chargeFees(harvestedBal);
        deposit();

        emit StratHarvest(msg.sender);
    }

    // performance fees
    function chargeFees(uint harvestedBal) internal {
        uint256 wmaticFeeBal = harvestedBal.mul(45).div(1000);

        uint256 callFeeAmount = wmaticFeeBal.mul(callFee).div(MAX_FEE);
        IERC20(wmatic).safeTransfer(tx.origin, callFeeAmount);

        uint256 beefyFeeAmount = wmaticFeeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(wmatic).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = wmaticFeeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(wmatic).safeTransfer(strategist, strategistFee);
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
            _deleverage();
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
    function userReserves() public view returns (uint256, uint256) {
        (uint256 supplyBal,,uint256 borrowBal,,,,,,) = IDataProvider(dataProvider).getUserReserveData(want, address(this));
        return (supplyBal, borrowBal);
    }

    // returns the user account data across all the reserves
    function userAccountData() public view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    ) {
        return ILendingPool(lendingPool).getUserAccountData(address(this));
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
        (uint256 supplyBal, uint256 borrowBal) = userReserves();
        return supplyBal.sub(borrowBal);
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
        IERC20(want).safeApprove(lendingPool, uint256(-1));
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(lendingPool, 0);
    }
} 