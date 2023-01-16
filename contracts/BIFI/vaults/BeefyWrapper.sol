// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

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
 * @dev Implementation of an ERC4626 wrapper for Beefy Vaults.
 * Depositing underlying tokens to this contract will transfer the Beefy Vault tokens from the
 * caller to this address and mint the wrapped version to the caller. Burning wrapped tokens
 * burns the wrapped version transferred by the caller, then withdraws the underlying tokens
 * from the Beefy vault and transfers those tokens back to the caller.
 */
contract BeefyWrapper is ERC4626Upgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    address public vault;

    /**
     * @dev Initializes an ERC4626 wrapper for a Beefy Vault token.
     * @param _vault the address of the vault.
     * @param _name the name of this contract's token.
     * @param _symbol the symbol of this contract's token.
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
     * @dev Wraps all vault share tokens owned by the caller.
     */
    function wrapAll() external {
        wrap(IERC20Upgradeable(vault).balanceOf(msg.sender));
    }

    /**
     * @dev Wraps an amount of vault share tokens.
     * @param amount the total amount of vault share tokens to be wrapped.
     */
    function wrap(uint256 amount) public {
        IERC20Upgradeable(vault).safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);
    }

    /**
     * @dev Unwraps all wrapped tokens owned by the caller.
     */
    function unwrapAll() external {
        unwrap(balanceOf(msg.sender));
    }

    /**
     * @dev Unwraps an amount of vault share tokens.
     * @param amount the total amount of vault share tokens to be unwrapped.
     */
    function unwrap(uint256 amount) public {
        _burn(msg.sender, amount);
        IERC20Upgradeable(vault).safeTransfer(msg.sender, amount);
    }

    /**
     * @dev Fetches the total assets held by the vault.
     * @return totalAssets the total balance of assets held by the vault.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return IVault(vault).balance();
    }

    /**
     * @dev Fetches the total vault shares.
     * @return totalSupply the total supply of vault shares.
     */
    function totalSupply()
        public view virtual override(ERC20Upgradeable, IERC20Upgradeable) 
    returns (uint256) {
        return IERC20Upgradeable(vault).totalSupply();
    }

    /**
     * @dev Deposit assets to the vault and mint an equal number of wrapped tokens to vault shares.
     * @param caller the address of the sender of the assets.
     * @param receiver the address of the receiver of the wrapped tokens.
     * @param assets the amount of assets being deposited.
     * @param shares the amount of shares being minted.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        IERC20Upgradeable(asset()).safeTransferFrom(caller, address(this), assets);
        uint balance = IERC20Upgradeable(vault).balanceOf(address(this));
        IVault(vault).deposit(assets);
        shares = IERC20Upgradeable(vault).balanceOf(address(this)) - balance;
        _mint(receiver, shares);

        emit Deposit(caller, receiver, assets, shares);
    }

    /**
     * @dev Burn wrapped tokens and withdraw assets from the vault.
     * @param caller the address of the caller of the withdraw.
     * @param receiver the address of the receiver of the assets.
     * @param owner the address of the owner of the burnt shares.
     * @param assets the amount of assets being withdrawn.
     * @param shares the amount of shares being burnt.
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

        IVault(vault).withdraw(shares);
        uint balance = IERC20Upgradeable(asset()).balanceOf(address(this));
        if (assets > balance) {
            assets = balance;
        }

        IERC20Upgradeable(asset()).safeTransfer(receiver, assets);

        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
