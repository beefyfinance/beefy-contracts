// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {ERC4626Upgradeable, ERC20Upgradeable, MathUpgradeable, IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SafeERC20Upgradeable, IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @dev Interface of a Beefy Vault
 */
interface IVault {
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function balance() external view returns (uint256);
    function want() external view returns (IERC20MetadataUpgradeable);
    function totalSupply() external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

/**
 * @title Beefy Wrapper ERC-4626
 * @author kexley
 * @notice Implementation for an ERC-4626 wrapper of a Beefy Vault
 * @dev Wrapped Beefy Vault tokens can be minted by deposit of the underlying asset or by 
 * wrapping Beefy Vault tokens in a 1:1 ratio. Wrapped Beefy Vault tokens can either be unwrapped
 * for an equal number of Beefy Vault tokens or redeemed for the underlying asset.
 * ERC4626 rules are strictly enforced, preview functions should return the correct values.
 * Only vaults which do not update their asset balance on deposit can be wrapped, i.e. vaults which
 * have profit locked or not harvesting on deposit, and the underlying balance is not updated on interactions.
 */
contract BeefyWrapper is ERC4626Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    /**
     * @notice Error for when the shares are not minted correctly
     */
    error MissingShares();

    /**
     * @notice Error for when the assets are not transferred correctly
     */
    error LeftOverAssets();

    /**
     * @notice Address of the vault being wrapped
     */
    address public vault;

    /**
     * @notice Initializes an ERC-4626 wrapper for a Beefy Vault token
     * @dev Called by the factory on cloning
     * @param _vault the address of the vault being wrapped
     * @param _name the name of the vault
     * @param _symbol the symbol of the vault's token
     */
     function initialize(
        address _vault,
        string memory _name,
        string memory _symbol
    ) public initializer {
        vault = _vault;
        __ERC20_init(_name, _symbol);
        __ERC4626_init(IVault(vault).want());

        IERC20Upgradeable(asset()).safeApprove(vault, type(uint256).max);
    }

    /**
     * @notice Wraps all vault tokens owned by the caller
     */
    function wrapAll() external {
        wrap(IERC20Upgradeable(vault).balanceOf(msg.sender));
    }

    /**
     * @notice Wraps an amount of vault tokens
     * @param amount the total amount of vault share tokens to be wrapped
     */
    function wrap(uint256 amount) public {
        IERC20Upgradeable(vault).safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    /**
     * @notice Unwraps all wrapped tokens owned by the caller
     */
    function unwrapAll() external {
        unwrap(balanceOf(msg.sender));
    }

    /**
     * @notice Unwraps an amount of vault tokens
     * @param amount the total amount of vault tokens to be unwrapped
     */
    function unwrap(uint256 amount) public {
        _burn(msg.sender, amount);
        IERC20Upgradeable(vault).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Fetches the total assets held by the vault
     * @dev Returns the total assets held by the vault, not only the wrapper
     * @return totalAssets the total balance of assets held by the vault
     */
    function totalAssets() public view virtual override returns (uint256) {
        return IVault(vault).balance();
    }

    /**
     * @notice Fetches the total vault shares
     * @dev Returns the total vault shares, not the shares of the wrapper
     * @return totalSupply the total supply of vault shares
     */
    function totalSupply()
        public view virtual override(ERC20Upgradeable, IERC20Upgradeable) 
    returns (uint256) {
        return IERC20Upgradeable(vault).totalSupply();
    }

    /**
     * @notice Deposit underlying assets to the vault and mint tokens to the receiver
     * @dev Overrides ERC-4626 internal deposit function. Deposits underlying assets to the vault 
     * and mints the increase in vault shares to the receiver
     * @param caller the address of the sender of the assets
     * @param receiver the address of the receiver of the wrapped tokens
     * @param assets the amount of assets being deposited
     * @param shares the amount of shares being minted
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        IERC20Upgradeable(asset()).safeTransferFrom(caller, address(this), assets);
        uint256 balance = IERC20Upgradeable(vault).balanceOf(address(this));

        IVault(vault).deposit(assets);

        /// Prevent harvest on deposit vaults from under-minting to the wrapper
        if (shares != IERC20Upgradeable(vault).balanceOf(address(this)) - balance) revert MissingShares();

        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @notice Burn tokens and withdraw assets to receiver
     * @dev Overrides ERC-4626 internal withdraw function. Withdraws the underlying asset from the 
     * vault and sends to the receiver
     * @param caller the address of the caller of the withdraw
     * @param receiver the address of the receiver of the assets
     * @param owner the address of the owner of the burnt shares
     * @param assets the amount of assets being withdrawn
     * @param shares the amount of shares being burnt
     */
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);

        uint256 balance = IERC20Upgradeable(asset()).balanceOf(address(this));

        IVault(vault).withdraw(shares);

        IERC20Upgradeable(asset()).safeTransfer(receiver, assets);

        /// Prevent assets from being left over in the wrapper
        if (IERC20Upgradeable(asset()).balanceOf(address(this)) > balance) revert LeftOverAssets();

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     */
    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding) internal view virtual override returns (uint256) {
        return assets.mulDiv(totalSupply(), totalAssets(), rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding) internal view virtual override returns (uint256) {
        return shares.mulDiv(totalAssets(), totalSupply(), rounding);
    }
}
