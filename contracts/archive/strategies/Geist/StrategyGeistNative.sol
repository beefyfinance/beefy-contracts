// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "../../interfaces/aave/IDataProvider.sol";
import "../../interfaces/geist/IMultiFeeDistributer.sol";
import "../../interfaces/geist/IIncentivesController.sol";
import "../../interfaces/aave/ILendingPool.sol";
import "../../interfaces/common/IUniswapRouter.sol";
import "../Common/FeeManager.sol";
import "../Common/StratManager.sol";

contract StrategyGeistNative is StratManager, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public want;
    address public output;
    address public native;

    struct TokenAddresses {
        address token;
        address gToken;
        address vToken;
    }

    TokenAddresses public wantTokens;
    TokenAddresses[] public rewards;

    // Third party contracts
    address public dataProvider = address(0xf3B0611e2E4D2cd6aB4bb3e01aDe211c3f42A8C3);
    address public lendingPool = address(0x9FAD24f572045c7869117160A571B2e50b10d068);
    address public multiFeeDistributer = address(0x49c93a95dbcc9A6A4D8f77E59c038ce5020e82f8);
    address public incentivesController = address(0x297FddC5c33Ef988dd03bd13e162aE084ea1fE57);

    // Routes
    address[] public outputToNativeRoute;
    address[][] public rewardToNativeRoutes;

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
    uint256 constant public INTEREST_RATE_MODE = 2;

    /**
     * @dev Helps to differentiate borrowed funds that shouldn't be used in functions like 'deposit()'
     * as they're required to deleverage correctly.
     */
    uint256 public reserves = 0;

    /**
     * @dev Events that the contract emits
     */
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event StratRebalance(uint256 _borrowRate, uint256 _borrowDepth);

    constructor(
        address _want,
        uint256[] memory _borrowConfig,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[][] memory _rewardToNativeRoutes
    ) StratManager(_keeper, _strategist, _unirouter, _vault, _beefyFeeRecipient) public {
        want = _want;

        borrowRate = _borrowConfig[0];
        borrowRateMax = _borrowConfig[1];
        borrowDepth = _borrowConfig[2];
        minLeverage = _borrowConfig[3];

        (address gToken,,address vToken) = IDataProvider(dataProvider).getReserveTokensAddresses(want);
        wantTokens = TokenAddresses(want, gToken, vToken);

        output = _outputToNativeRoute[0];
        native = _outputToNativeRoute[_outputToNativeRoute.length - 1];

        outputToNativeRoute = _outputToNativeRoute;
        rewardToNativeRoutes = _rewardToNativeRoutes;

        for (uint256 i; i < rewardToNativeRoutes.length; i++) {
            address _token = rewardToNativeRoutes[i][0];
            (address _gToken,,address _vToken) = IDataProvider(dataProvider).getReserveTokensAddresses(_token);
            rewards.push(TokenAddresses(_token, _gToken, _vToken));
        }

        _giveAllowances();
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
            ILendingPool(lendingPool).deposit(want, _amount, address(this), 0);
            _amount = _amount.mul(borrowRate).div(100);
            if (_amount > 0) {
                ILendingPool(lendingPool).borrow(want, _amount, INTEREST_RATE_MODE, 0, address(this));
            }
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
        uint256 adjBorrowRate = borrowRate > 1 ? borrowRate.sub(1) : borrowRate;

        while (wantBal < borrowBal) {
            ILendingPool(lendingPool).repay(want, wantBal, INTEREST_RATE_MODE, address(this));

            (supplyBal, borrowBal) = userReserves();
            uint256 targetSupply = borrowBal.mul(100).div(adjBorrowRate);

            ILendingPool(lendingPool).withdraw(want, supplyBal.sub(targetSupply), address(this));
            wantBal = IERC20(want).balanceOf(address(this));
        }

        if (borrowBal > 0) {
            ILendingPool(lendingPool).repay(want, uint256(-1), INTEREST_RATE_MODE, address(this));
        }
        if (supplyBal > 0) {
            ILendingPool(lendingPool).withdraw(want, type(uint).max, address(this));
        }

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
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        uint256 gTokenBal = IERC20(wantTokens.gToken).balanceOf(address(this));
        address[] memory tokens = new address[](2);
        tokens[0] = wantTokens.gToken;
        tokens[1] = wantTokens.vToken;
        IIncentivesController(incentivesController).claim(address(this), tokens);
        IMultiFeeDistributer(multiFeeDistributer).exit();

        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient, gTokenBal);
            uint256 wantHarvested = availableWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    // performance fees
    function chargeFees(address callFeeRecipient, uint256 gTokenBal) internal {
        uint256 beforeBal = IERC20(native).balanceOf(address(this));
        uint256 toNative = IERC20(output).balanceOf(address(this));
        IUniswapRouter(unirouter).swapExactTokensForTokens(toNative, 0, outputToNativeRoute, address(this), now);

        for (uint i; i < rewards.length; i++) {
            toNative = IERC20(rewards[i].gToken).balanceOf(address(this));
            if (rewards[i].gToken == wantTokens.gToken) {
                if (toNative > gTokenBal) {
                    toNative -= gTokenBal;
                } else {toNative = 0;}
            }
            if (toNative > 0) {
                ILendingPool(lendingPool).withdraw(rewards[i].token, toNative, address(this));
                if (rewards[i].token != native) {
                    IUniswapRouter(unirouter).swapExactTokensForTokens(toNative, 0, rewardToNativeRoutes[i], address(this), now);
                }
            }
        }

        uint256 nativeBal = IERC20(native).balanceOf(address(this)).sub(beforeBal).mul(45).div(1000);

        uint256 callFeeAmount = nativeBal.mul(callFee).div(MAX_FEE);
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal.mul(beefyFee).div(MAX_FEE);
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFee = nativeBal.mul(STRATEGIST_FEE).div(MAX_FEE);
        IERC20(native).safeTransfer(strategist, strategistFee);
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

    // returns rewards unharvested
    function rewardsAvailable() public view returns (uint256[] memory) {
        address[] memory incentivisedTokens = new address[](2);
        incentivisedTokens[0] = wantTokens.gToken;
        incentivisedTokens[1] = wantTokens.vToken;
        uint256[] memory geistReward = new uint256[](2);
        IMultiFeeDistributer.RewardData[] memory rewardAmounts = new IMultiFeeDistributer.RewardData[](rewards.length);

        geistReward = IIncentivesController(incentivesController).claimableReward(address(this), incentivisedTokens);
        rewardAmounts = IMultiFeeDistributer(multiFeeDistributer).claimableRewards(address(this));

        uint256[] memory amounts = new uint256[](rewards.length + 1);
        amounts[0] = geistReward[0].add(geistReward[1]).div(2);
        for (uint i = 1; i < rewards.length + 1; i++) {
            amounts[i] = rewardAmounts[i].amount;
        }

        return amounts;
    }

    // native reward amount for calling harvest
    function callReward() public view returns (uint256) {
        uint256[] memory outputBals = rewardsAvailable();
        uint256 nativeOut;

        try IUniswapRouter(unirouter).getAmountsOut(outputBals[0], outputToNativeRoute)
        returns (uint256[] memory amountOut) {
            nativeOut = amountOut[amountOut.length - 1];
        }
        catch {}

        for (uint i; i < rewards.length; i++) {
            if (outputBals[i + 1] > 0) {
                if (rewards[i].token != native) {
                    try IUniswapRouter(unirouter).getAmountsOut(outputBals[i + 1], rewardToNativeRoutes[i])
                    returns (uint256[] memory amountOut)
                    {
                        nativeOut += amountOut[amountOut.length - 1];
                    }
                    catch {}
                } else {
                    nativeOut += outputBals[i + 1];
                }
            }
        }

        return nativeOut.mul(45).div(1000).mul(callFee).div(MAX_FEE);
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

        IERC20(output).safeApprove(unirouter, uint256(-1));
        for (uint i; i < rewards.length; i++) {
            IERC20(rewards[i].token).safeApprove(unirouter, uint256(-1));
        }
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(lendingPool, 0);

        IERC20(output).safeApprove(unirouter, 0);
        for (uint i; i < rewards.length; i++) {
            IERC20(rewards[i].token).safeApprove(unirouter, 0);
        }
    }

    function addRewardToNativeRoute(address[] memory _rewardToNativeRoute) external onlyOwner {
        address _token = _rewardToNativeRoute[0];
        (address _gToken,,address _vToken) = IDataProvider(dataProvider).getReserveTokensAddresses(_token);

        rewards.push(TokenAddresses(_token, _gToken, _vToken));
        rewardToNativeRoutes.push(_rewardToNativeRoute);

        IERC20(_token).safeApprove(unirouter, uint256(-1));
    }

    function removeRewardToNativeRoute() external onlyOwner {
        IERC20(rewards[rewards.length -1].token).safeApprove(unirouter, 0);

        rewards.pop();
        rewardToNativeRoutes.pop();
    }

    function outputToNative() public view returns (address[] memory) {
        return outputToNativeRoute;
    }

    function rewardToNative() public view returns (address[][] memory) {
        return rewardToNativeRoutes;
    }
}