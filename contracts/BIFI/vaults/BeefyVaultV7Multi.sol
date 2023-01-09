// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./VaultManager.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract BeefyVaultV7Multi is VaultManager, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    event Reported(
        address indexed strategy,
        int256 roi,
        uint256 repayment,
        uint256 gains,
        uint256 losses,
        uint256 allocated,
        uint256 debtRatio
    );

    /**
     * @dev Sets the value of {token} to the token that the vault will
     * hold as underlying value. It initializes the vault's own 'moo' token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     * @param _asset The asset to maximize.
     * @param _name The name of the vault asset.
     * @param _symbol The symbol of the vault asset.
     * @param _tvlCap Initial deposit cap for scaling TVL safely.
     * @param _keeper The address of the admin managing the vault.
     */
    function initialize(
        IERC20MetadataUpgradeable _asset,
        string memory _name,
        string memory _symbol,
        uint256 _tvlCap,
        address _keeper
    ) public initializer {
        __ERC4626_init(_asset);
        __ERC20_init(_name, _symbol);
        __Manager_init_(_tvlCap, _keeper);
    }

    /**
     * @dev It calculates the total underlying value of {asset} held by the system.
     * It takes into account the vault contract balance, and the balance deployed across
     * all the strategies.
     * @return totalAssets The total amount of assets managed by the vault.
     */
    function totalAssets() public virtual override view returns (uint256) {
        return _availableBalance() + totalAllocated;
    }

    /**
     * @dev It fetches the amount of funds on this contract.
     * @return availableBalance The amount of funds on this contract.
     */
    function _availableBalance() internal virtual view returns (uint256) {
        return IERC20Upgradeable(asset()).balanceOf(address(this));
    }

    /**
     * @dev It calculates the amount of free funds available after profit locking.
     * For calculating share price and making withdrawals.
     * @return freeFunds The total amount of free funds available.
     */
    function _freeFunds() internal virtual view returns (uint256) {
        return totalAssets() - _calculateLockedProfit();
    }

    /**
     * @dev It calculates the amount of locked profit from recent harvests.
     * @return lockedProfit The amount of locked profit.
     */
    function _calculateLockedProfit() internal virtual view returns (uint256) {
        uint256 lockedFundsRatio = (block.timestamp - lastReport) * lockedProfitDegradation;

        if (lockedFundsRatio < DEGRADATION_COEFFICIENT) {
            return lockedProfit - (
                lockedFundsRatio
                * lockedProfit
                / DEGRADATION_COEFFICIENT
            );
        } else {
            return 0;
        }
    }

    /**
     * @dev The amount of shares that the Vault would exchange for the amount of assets provided,
     * in an ideal scenario where all the conditions are met. Overrides the ERC4626 function to use
     * _freeFunds() instead of totalAssets() for converting to the correct amount of shares.
     * @param assets The amount of underlying assets to convert to shares.
     * @param rounding The direction to round the calculation.
     * @return shares The amount of shares given for the amount of assets.
     */
    function _convertToShares(
        uint256 assets, 
        MathUpgradeable.Rounding rounding
    ) internal virtual override view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        uint256 freeFunds = _freeFunds();
        if (freeFunds == 0 || _totalSupply == 0) return assets;
        return assets.mulDiv(_totalSupply, freeFunds, rounding);
    }

    /**
     * @dev The amount of assets that the Vault would exchange for the amount of shares provided,
     * in an ideal scenario where all the conditions are met. Overrides the ERC4626 function to use
     * _freeFunds() instead of totalAssets() for converting to the correct amount of assets.
     * @param shares The amount of shares to convert to underlying assets.
     * @param rounding The direction to round the calculation.
     * @return assets The amount of assets given for the amount of shares.
     */
    function _convertToAssets(
        uint256 shares,
        MathUpgradeable.Rounding rounding
    ) internal virtual override view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return shares;
        return shares.mulDiv(_freeFunds(), _totalSupply, rounding);
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * @return pricePerFullShare how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() external virtual view returns (uint256) {
        return convertToAssets(1 ether);
    }

    /**
     * @dev Maximum amount of the underlying asset that can be deposited into the Vault for the 
     * receiver, through a deposit call.
     * @return maxAssets The maximum depositable assets.
     */
    function maxDeposit(address) public virtual override view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        if (_totalAssets > tvlCap) {
            return 0;
        }
        return tvlCap - _totalAssets;
    }

    /**
     * @dev Maximum amount of shares that can be minted from the Vault for the receiver, through a 
     * mint call.
     * @return shares The maximum amount of shares issued from calling mint.
     */
    function maxMint(address) public virtual override view returns (uint256) {
        return convertToShares(maxDeposit(address(0)));
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external virtual {
        deposit(IERC20Upgradeable(asset()).balanceOf(msg.sender), msg.sender);
    }

    /**
     * @dev A helper function to call redeem() with all the sender's funds.
     */
    function withdrawAll() external virtual {
        redeem(balanceOf(msg.sender), msg.sender, msg.sender);
    }

    /**
     * @dev A helper function to call redeem() with all the sender's funds.
     */
    function redeemAll() external virtual {
        redeem(balanceOf(msg.sender), msg.sender, msg.sender);
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault.
     * @param caller the caller of the deposit function.
     * @param receiver the receiver of the minted shares.
     * @param assets the amount of assets to deposit.
     * @param shares the amount of shares issued from the deposit.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal nonReentrant virtual override {
        require(!emergencyShutdown, "emergencyShutdown");

        IERC20Upgradeable(asset()).safeTransferFrom(caller, address(this), assets);

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);
    }

    /**
     * @dev Internal function used by both withdraw and redeem to withdraw assets.
     * It checks for spend allowance if the caller is not the owner. Assets are withdrawn from the
     * strategies in the order of the withdrawal queue.
     * @param caller The caller of the deposit function.
     * @param receiver The receiver of the withdrawn assets.
     * @param owner The owner of the shares to withdraw.
     * @param assets The amount of assets to withdraw.
     * @param shares The amount of shares to burn.
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal nonReentrant virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);

        if (assets > _availableBalance()) {
            uint256 totalLoss = 0;
            uint256 queueLength = withdrawalQueue.length;
            uint256 vaultBalance = 0;

            for (uint256 i; i < queueLength;) {
                vaultBalance = _availableBalance();
                if (vaultBalance >= assets) {
                    break;
                }

                address stratAddr = withdrawalQueue[i];
                uint256 strategyBal = strategies[stratAddr].allocated;
                if (strategyBal == 0) {
                    continue;
                }

                uint256 remaining = assets - vaultBalance;
                uint256 loss = IMultiStrategy(stratAddr).withdraw(
                    MathUpgradeable.min(remaining, strategyBal)
                );
                uint256 actualWithdrawn = _availableBalance() - vaultBalance;

                // Withdrawer incurs any losses from withdrawing as reported by strat
                if (loss != 0) {
                    assets -= loss;
                    totalLoss += loss;
                    _reportLoss(stratAddr, loss);
                }

                strategies[stratAddr].allocated -= actualWithdrawn;
                totalAllocated -= actualWithdrawn;
                unchecked { ++i; }
            }

            vaultBalance = _availableBalance();
            if (assets > vaultBalance) {
                assets = vaultBalance;
            }

            uint256 maxLoss = ((assets + totalLoss) * withdrawMaxLoss) / PERCENT_DIVISOR;

            require(totalLoss <= maxLoss, ">maxLoss");
        }

        IERC20Upgradeable(asset()).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @dev Called by a strategy to determine the amount of capital that the vault is
     * able to provide it. A positive amount means that vault has excess capital to provide
     * the strategy, while a negative amount means that the strategy has a balance owing to
     * the vault.
     * @param strategy The strategy address to check the credit/debit amount for.
     * @return availableCapital The amount of capital the vault can provide the strategy.
     */
    function availableCapital(address strategy) public virtual view returns (int256) {
        if (totalDebtRatio == 0 || emergencyShutdown) {
            return -int256(strategies[strategy].allocated);
        }

        uint256 stratMaxAllocation = 
            (strategies[strategy].debtRatio * totalAssets()) / PERCENT_DIVISOR;
        uint256 stratCurrentAllocation = strategies[strategy].allocated;

        if (stratCurrentAllocation >= stratMaxAllocation) {
            // Strategy owes the vault
            return -int256(stratCurrentAllocation - stratMaxAllocation);
        } else {
            // Vault owes the strategy
            uint256 vaultMaxAllocation = (totalDebtRatio * totalAssets()) / PERCENT_DIVISOR;
            uint256 vaultCurrentAllocation = totalAllocated;

            if (vaultCurrentAllocation >= vaultMaxAllocation) {
                return 0;
            }

            // Credit the strategy either what is left of the strategy allocation, leftovers from 
            // total vault allocation or available funds on the vault, whichever is smallest.
            uint256 available = stratMaxAllocation - stratCurrentAllocation;
            available = MathUpgradeable.min(available, vaultMaxAllocation - vaultCurrentAllocation);
            available = MathUpgradeable.min(available, _availableBalance());

            return int256(available);
        }
    }

    /**
     * @dev Helper function to report a loss by a given strategy.
     * @param strategy The strategy to report the loss for.
     * @param loss The amount lost.
     */
    function _reportLoss(address strategy, uint256 loss) internal virtual {
        StrategyParams storage stratParams = strategies[strategy];
        // Loss can only be up the amount of capital allocated to the strategy
        uint256 allocation = stratParams.allocated;
        require(loss <= allocation, "loss>allocation");

        if (totalDebtRatio != 0) {
            // Reduce strat's debtRatio proportional to loss
            uint256 bpsChange = MathUpgradeable.min(
                (loss * totalDebtRatio) / totalAllocated,
                stratParams.debtRatio
            );

            // If the loss is too small, bpsChange will be 0
            if (bpsChange != 0) {
                stratParams.debtRatio -= bpsChange;
                totalDebtRatio -= bpsChange;
            }
        }

        // Finally, adjust our strategy's parameters by the loss
        stratParams.losses += loss;
        stratParams.allocated -= loss;
        totalAllocated -= loss;
    }

    /**
     * @dev Report the strategy returns on a harvest and exchange funds with the vault depending on
     * owed amounts.
     * @param roi The return on investment (positive or negative) given as the total amount
     * gained or lost from the harvest.
     * @param repayment The repayment of debt by the strategy.
     * @return debt The strategy debt to the vault yet to be paid.
     */
    function report(int256 roi, uint256 repayment) external onlyStrategy virtual returns (uint256) {
        address stratAddr = msg.sender;
        StrategyParams storage strategy = strategies[stratAddr];
        uint256 loss = 0;
        uint256 gain = 0;

        if (roi < 0) {
            loss = uint256(-roi);
            _reportLoss(stratAddr, loss);
        } else {
            gain = uint256(roi);
            strategy.gains += gain;
        }

        // Fetch amount owed and adjust allocations
        int256 available = availableCapital(stratAddr);
        uint256 debt = 0;
        uint256 credit = 0;
        if (available < 0) {
            debt = uint256(-available);
            repayment = MathUpgradeable.min(debt, repayment);

            if (repayment != 0) {
                strategy.allocated -= repayment;
                totalAllocated -= repayment;
                debt -= repayment;
            }
        } else {
            credit = uint256(available);
            strategy.allocated += credit;
            totalAllocated += credit;
        }

        uint256 totalAvailable = repayment + gain;

        // Give/take balance to strategy based on the difference between the gains, debt payment,
        // the credit increase and the debt needed to be paid off.
        if (credit > totalAvailable) {
            IERC20Upgradeable(asset()).safeTransfer(stratAddr, credit - totalAvailable);
        } else if (credit < totalAvailable) {
            IERC20Upgradeable(asset()).safeTransferFrom(
                stratAddr,
                address(this),
                totalAvailable - credit
            );
        }

        // Lock profits for a period to prevent harvest thefts
        uint256 lockedProfitBeforeLoss = _calculateLockedProfit() + gain;
        if (lockedProfitBeforeLoss > loss) {
            lockedProfit = lockedProfitBeforeLoss - loss;
        } else {
            lockedProfit = 0;
        }

        strategy.lastReport = block.timestamp;
        lastReport = block.timestamp;

        emit Reported(
            stratAddr,
            roi,
            repayment,
            strategy.gains,
            strategy.losses,
            strategy.allocated,
            strategy.debtRatio
        );

        if (strategy.debtRatio == 0 || emergencyShutdown) {
            return IMultiStrategy(stratAddr).balanceOf();
        }

        return debt;
    }
}
