// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-4/contracts/access/Ownable.sol";

interface IVToken {
    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
}

interface IStrategy {
    function updateBalance() external;
    function harvest() external;
}

interface IBeefyVault {
    function upgradeStrat() external;
    function transferOwnership(address _owner) external;
    function balance() external view returns (uint256);
    function strategy() external view returns (address);
    function owner() external view returns (address);
}

interface IPair {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

// Built to safely flash loan amount needed to upgrade Beefy Vault to new strategy 
contract RescuerFrax is Ownable {
    using SafeERC20 for IERC20;

    // Addresses needed for the operation 
    IERC20 public frax = IERC20(0xdc301622e621166BD8E82f2cA0A26c13Ad0BE355);
    IBeefyVault public beefyVault = IBeefyVault(0xb8EddAA94BB8AbF8A5BB90c217D53960242e104D);
    IPair public fraxPair = IPair(0x4bBd8467ccd49D5360648CE14830f43a7fEB6e45);
    IVToken public iToken = IVToken(0x4E6854EA84884330207fB557D1555961D85Fc17E);

    event Rescued(uint256 fee, uint256 time);
    event VaultOwnershipChanged(address oldOwner, address newOwner);

    constructor() {
        // Approve frax for spend by iToken
        frax.safeApprove(address(iToken), type(uint).max);
    }

    // Vault Balance - Balance of FRAX in the iToken address is amount needed to withdraw fully.
    function fraxNeeded() public view returns (uint256) {
        return beefyVault.balance() - frax.balanceOf(address(iToken));
    }

    // We can grab the total fee as .0001 / .9999 since Solidly charges .01% fees.
    function getTotalFlashFee(uint256 _fraxNeeded) public pure returns (uint256) {
        return (_fraxNeeded * 0.000100010002 ether) / 1 ether;
    }

    // Flash Loan the difference needed, preform upgrade and return funds plus fee
    function upgrade() external onlyOwner {
        // Update Balances to ensure we grab the correct amount needed
        IStrategy(beefyVault.strategy()).updateBalance();
        // Transfer the flash fee from msg.sender
        frax.safeTransferFrom(msg.sender, address(this), getTotalFlashFee(fraxNeeded()));
        // Start Flash Loan
        fraxPair.swap(0, fraxNeeded(), address(this), "BeefyRescue");
    }

    // Finish FlashSwap & Upgrade
    function hook(address, uint, uint amount1, bytes calldata) external {
        require(msg.sender == address(fraxPair), "!pair");
        
        // Supply collateral with loaned amount + fee, upgrade and withdraw collateral
        iToken.mint(frax.balanceOf(address(this)));
        beefyVault.upgradeStrat();
        iToken.redeem(IERC20(address(iToken)).balanceOf(address(this)));

        // Pay our debts (Flash Loan capital + Fee)
        uint256 debt = amount1 + getTotalFlashFee(amount1);
        frax.safeTransfer(address(fraxPair), debt);
        
        emit Rescued(debt - amount1, block.timestamp);
    }

    function transferBeefyVaultOwnership(address _newOwner) external onlyOwner { 
        emit VaultOwnershipChanged(beefyVault.owner(), _newOwner);
        beefyVault.transferOwnership(_newOwner);
    }

     function inCaseTokensGetStuck(address _token) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
    }
}