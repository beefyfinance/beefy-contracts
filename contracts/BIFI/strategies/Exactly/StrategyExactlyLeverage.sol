// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/utils/math/Math.sol";

import "../../utils/UniswapV3Utils.sol";
import "../../interfaces/exactly/IExactlyMarket.sol";
import "../../interfaces/exactly/IExactlyAuditor.sol";
import "../../interfaces/exactly/IExactlyRewardsController.sol";
import "../../interfaces/beethovenx/IBalancerVault.sol";
import "../Common/StratFeeManagerInitializable.sol";

contract StrategyExactlyLeverage is StratFeeManagerInitializable {
    using SafeERC20 for IERC20;

    struct InitialVariables {
        address eToken;
        uint256 targetLtv;
        uint256 maxLtv;
        uint256 range;
        uint256 minLeverage;
        address balancerVault;
        address rewardsController;
    }

    struct Routes {
        address[] outputToNativeRoute;
        uint24[] outputToNativeFees;
        address[] outputToWantRoute;
        uint24[] outputToWantFees;
    }

    // Tokens used
    address public want;
    address public output;
    address public native;
    address public eToken;

    // Third party contracts
    address public balancerVault;
    address public rewardsController;

    // Routes
    bytes public outputToNativePath;
    bytes public outputToWantPath;

    bool public harvestOnDeposit;
    uint256 public lastHarvest;
    bool private flashloanCalled;

    // LTV
    uint256 public targetLtv;
    uint256 public lowLtv;
    uint256 public highLtv;
    uint256 public maxLtv;
    uint256 public minLeverage;

    /**
     * @dev Events that the contract emits
     */
    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);
    event StratRebalance(uint256 targetLtv, uint256 range);

    function initialize(
        InitialVariables calldata _initialVariables,
        Routes calldata _routes,
        CommonAddresses calldata _commonAddresses
    ) public initializer {
        __StratFeeManager_init(_commonAddresses);
        eToken = _initialVariables.eToken;

        want = _routes.outputToWantRoute[_routes.outputToWantRoute.length - 1];
        native = _routes.outputToNativeRoute[_routes.outputToNativeRoute.length - 1];
        output = _routes.outputToWantRoute[0];

        targetLtv = _initialVariables.targetLtv;
        maxLtv = _initialVariables.maxLtv;
        lowLtv = targetLtv > (_initialVariables.range / 2) 
            ? targetLtv - (_initialVariables.range / 2) 
            : 0;
        highLtv = targetLtv + (_initialVariables.range / 2);
        require(highLtv < maxLtv, ">maxLtv");
        minLeverage = _initialVariables.minLeverage;

        balancerVault = _initialVariables.balancerVault;
        rewardsController = _initialVariables.rewardsController;

        address auditor = IExactlyMarket(eToken).auditor();
        IExactlyAuditor(auditor).enterMarket(eToken);

        outputToNativePath = UniswapV3Utils.routeToPath(_routes.outputToNativeRoute, _routes.outputToNativeFees);
        outputToWantPath = UniswapV3Utils.routeToPath(_routes.outputToWantRoute, _routes.outputToWantFees);

        _giveAllowances();
    }

    /**
     * @dev Puts the funds to work
     */
    function deposit() public whenNotPaused {
        uint256 wantBal = balanceOfWant();

        if (wantBal > 0) {
            _leverage();
            emit Deposit(balanceOf());
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault
     * @param _amount How much {want} to withdraw.
     */
    function withdraw(uint256 _amount) external {
        require(msg.sender == vault, "!vault");

        uint256 wantBal = balanceOfWant();
        if (wantBal < _amount) {
            _deleverage(_amount);
            wantBal = balanceOfWant();
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
    }

    /**
     * @dev Supplies want to Exactly and then performs a flashloan to achieve the target LTV
     */
    function _leverage() internal {
        IExactlyMarket(eToken).deposit(balanceOfWant(), address(this));
        (,,uint256 currentLtv) = getSupplyBorrow();
        if (currentLtv < lowLtv || currentLtv > highLtv) {
            _upkeep();
        }
    }

    /**
     * @dev Withdraws directly from Exactly if the new LTV doesn't exceed the target LTV. Otherwise 
     * the supply and borrow needs to be reduced by an amount to achieve the target LTV, and then 
     * an extra amount needs to withdrawn while maintaining target LTV.
     * @param _amount funds to withdraw from the lending pools
     */
    function _deleverage(uint256 _amount) internal {
        (uint256 supplyBal, uint256 borrowBal, uint256 currentLtv) = getSupplyBorrow();
        uint256 newLtv = _amount < supplyBal ? borrowBal * 1 ether / (supplyBal - _amount) : 0;

        if (newLtv <= highLtv) {
            IExactlyMarket(eToken).withdraw(_amount, address(this), address(this));
        } else {
            uint256 rebalanceAmount = currentLtv > targetLtv 
                ? supplyBal * (currentLtv - targetLtv) / (1 ether - targetLtv) 
                : 0;
            uint256 withdrawAmount = _amount * targetLtv / (1 ether - targetLtv);

            uint256 flashAmount = rebalanceAmount + withdrawAmount;
            uint256 balancerBal = IERC20(want).balanceOf(balancerVault);

            if (flashAmount > balancerBal) {
                flashAmount = balancerBal;
                newLtv = (borrowBal - flashAmount) * 1 ether / (supplyBal - flashAmount - _amount);
                require(newLtv <= highLtv, "!availableFlashLiq");
            }
            _flashLoanDown(flashAmount, _amount);
        }
    }

    /**
     * @dev Start the flashloan to increase borrow and supply on Exactly
     * @param _amount funds to borrow from Balancer
     */
    function _flashLoanUp(uint256 _amount) internal {
        bytes memory data = abi.encode(false, 0);
        _flashLoan(_amount, data);
    }

    /**
     * @dev Start the flashloan to decrease borrow and supply on Exactly
     * @param _amount funds to borrow from Balancer
     * @param _withdrawAmount funds to withdraw from Exactly to fulfull a user withdrawal
     */
    function _flashLoanDown(uint256 _amount, uint256 _withdrawAmount) internal {
        bytes memory data = abi.encode(true, _withdrawAmount);
        _flashLoan(_amount, data);
    }

    /**
     * @dev Start the flashloan on Exactly
     * @param _amount funds to borrow from Balancer
     * @param _data encoded (bool, uint) amount to withdraw to fulfull a possible user withdrawal
     */
    function _flashLoan(uint256 _amount, bytes memory _data) internal {
        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        assets[0] = want;
        amounts[0] = _amount;
        flashloanCalled = true;
        IBalancerVault(balancerVault).flashLoan(address(this), assets, amounts, _data);
    }

    /**
     * @dev Callback from Balancer vault during flashloan. Withdrawals use the flashloan to repay
     * the amount, withdraw exactly the same amount and an additional amount to pay the user 
     * withdrawal then repay the flashloan. Deposits use the flashloan to supply the amount, borrow
     * exactly the same amount and repay the flashloan. Balancer flashloans have 0 fees for now.
     */
    function receiveFlashLoan(
        address[] memory,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external returns (bool) {
        require(msg.sender == balancerVault && flashloanCalled, "!caller");
        flashloanCalled = false;
        (bool withdrawing, uint256 withdrawAmount) = abi.decode(userData, (bool, uint256));

        if (withdrawing) {
            (uint256 actualRepay,) = IExactlyMarket(eToken).repay(amounts[0], address(this));
            IExactlyMarket(eToken).withdraw(actualRepay + withdrawAmount, address(this), address(this));
            IERC20(want).safeTransfer(balancerVault, amounts[0] + feeAmounts[0]);
        } else {
            IExactlyMarket(eToken).deposit(amounts[0], address(this));
            IExactlyMarket(eToken).borrow(amounts[0] + feeAmounts[0], address(this), address(this));
            IERC20(want).safeTransfer(balancerVault, amounts[0] + feeAmounts[0]);
        }

        return true;
    }

    /**
     * @dev Updates the risk profile and rebalances the vault funds accordingly
     * @param _targetLtv new LTV ratio on Exactly
     * @param _range total sway the LTV can move before rebalancing occurs
     */
    function rebalance(uint256 _targetLtv, uint256 _range) external onlyManager {
        targetLtv = _targetLtv;
        lowLtv = targetLtv > (_range / 2) ? targetLtv - (_range / 2) : 0;
        highLtv = targetLtv + (_range / 2);
        require(highLtv < maxLtv, ">maxLtv");

        _upkeep();

        emit StratRebalance(targetLtv, _range);
    }

    /**
     * @dev Helper function to resets the current LTV back to the target
     */
    function upkeep() external onlyManager {
        _upkeep();
    }

    /**
     * @dev Internal function that keeps the current LTV close to the target
     */
    function _upkeep() internal {
        (uint256 supplyBal, uint256 borrowBal, uint256 currentLtv) = getSupplyBorrow();
        uint256 rebalanceAmount;

        if (targetLtv == 0) {
            rebalanceAmount = Math.min(borrowBal, IERC20(want).balanceOf(balancerVault));
            if (rebalanceAmount > 0) _flashLoanDown(rebalanceAmount, 0);
        } else if (currentLtv > targetLtv) {
            rebalanceAmount = Math.min(
                supplyBal * (currentLtv - targetLtv) / (1 ether - targetLtv),
                IERC20(want).balanceOf(balancerVault)
            );
            _flashLoanDown(rebalanceAmount, 0);
        } else {
            uint256 extraSupply = supplyBal - (borrowBal * 1 ether / targetLtv);
            rebalanceAmount = Math.min(
                extraSupply * targetLtv / (1 ether - targetLtv),
                IERC20(want).balanceOf(balancerVault)
            );
            _flashLoanUp(rebalanceAmount);
        }
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

    /**
     * @dev Compounds earnings and charges performance fee
     */
    function _harvest(address callFeeRecipient) internal whenNotPaused {
        IExactlyRewardsController(rewardsController).claimAll(address(this));
        uint256 outputBal = IERC20(output).balanceOf(address(this));
        if (outputBal > 0) {
            chargeFees(callFeeRecipient);
            swapRewards();
            uint256 wantHarvested = balanceOfWant();
            deposit();

            lastHarvest = block.timestamp;
            emit StratHarvest(msg.sender, wantHarvested, balanceOf());
        }
    }

    /**
     * @dev Performance fees
     */
    function chargeFees(address callFeeRecipient) internal {
        IFeeConfig.FeeCategory memory fees = getFees();
        uint256 toNative = IERC20(output).balanceOf(address(this)) * fees.total / DIVISOR;
        UniswapV3Utils.swap(unirouter, outputToNativePath, toNative);

        uint256 nativeBal = IERC20(native).balanceOf(address(this));

        uint256 callFeeAmount = nativeBal * fees.call / DIVISOR;
        IERC20(native).safeTransfer(callFeeRecipient, callFeeAmount);

        uint256 beefyFeeAmount = nativeBal * fees.beefy / DIVISOR;
        IERC20(native).safeTransfer(beefyFeeRecipient, beefyFeeAmount);

        uint256 strategistFeeAmount = nativeBal * fees.strategist / DIVISOR;
        IERC20(native).safeTransfer(strategist, strategistFeeAmount);

        emit ChargedFees(callFeeAmount, beefyFeeAmount, strategistFeeAmount);
    }

    /**
     * @dev Swap rewards to want
     */
    function swapRewards() internal {
        if (output != want) {
            uint256 toWant = IERC20(output).balanceOf(address(this));
            UniswapV3Utils.swap(unirouter, outputToWantPath, toWant);
        }
    }

    /**
     * @dev Fetch the supply and borrow balances from Exactly
     * @return supplyBal supply balance
     * @return borrowBal borrow balance
     * @return currentLtv LTV on Exactly
     */
    function getSupplyBorrow() public view returns (uint256 supplyBal, uint256 borrowBal, uint256 currentLtv) {
        (supplyBal, borrowBal) = IExactlyMarket(eToken).accountSnapshot(address(this));
        currentLtv = supplyBal > 0 ? borrowBal * 1 ether / supplyBal : 0;
    }

    // calculate the total underlaying 'want' held by the strat.
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool();
    }

    // it calculates how much 'want' this contract holds.
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    // it calculates how much 'want' the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 supplyBal, uint256 borrowBal,) = getSupplyBorrow();
        return supplyBal - borrowBal;
    }

    // returns rewards unharvested
    function rewardsAvailable() external view returns (uint256) {
        return IExactlyRewardsController(rewardsController).allClaimable(address(this), output);
    }

    // native reward amount for calling harvest
    function callReward() external pure returns (uint256) {
        return 0;
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

        (,uint256 borrowBal,) = getSupplyBorrow();
        while (borrowBal > 0) {
            _flashLoanDown(Math.min(borrowBal, IERC20(want).balanceOf(balancerVault)), 0);
            (,borrowBal,) = getSupplyBorrow();
        }
        
        uint256 eTokenBal = IERC20(eToken).balanceOf(address(this));
        if (eTokenBal > 0) IExactlyMarket(eToken).redeem(eTokenBal, address(this), address(this));

        uint256 wantBal = balanceOfWant();
        IERC20(want).transfer(vault, wantBal);
    }

    // pauses deposits and withdraws all funds from third party systems.
    function panic() public onlyManager {
        (,uint256 borrowBal,) = getSupplyBorrow();
        while (borrowBal > 0) {
            _flashLoanDown(Math.min(borrowBal, IERC20(want).balanceOf(balancerVault)), 0);
            (,borrowBal,) = getSupplyBorrow();
        }
        
        uint256 eTokenBal = IERC20(eToken).balanceOf(address(this));
        if (eTokenBal > 0) IExactlyMarket(eToken).redeem(eTokenBal, address(this), address(this));

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
        IERC20(want).safeApprove(eToken, type(uint).max);
        IERC20(output).safeApprove(unirouter, type(uint).max);
    }

    function _removeAllowances() internal {
        IERC20(want).safeApprove(eToken, 0);
        IERC20(output).safeApprove(unirouter, 0);
    }

    function outputToNative() public view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(outputToNativePath);
    }

    function outputToWant() public view returns (address[] memory) {
        return UniswapV3Utils.pathToRoute(outputToWantPath);
    }
}