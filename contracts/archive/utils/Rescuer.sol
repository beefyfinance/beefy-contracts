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

interface IBalancerVault {
    function flashLoan(address recipient, address[] calldata tokens, uint256[] calldata amounts, bytes calldata userdata) external;
}

// Built to safely flash loan amount needed to upgrade Beefy Vault to new strategy 
contract Rescuer is Ownable {
    using SafeERC20 for IERC20;

    // Addresses needed for the operation 
    IERC20 public tusd = IERC20(0x9879aBDea01a879644185341F7aF7d8343556B7a);
    IBeefyVault public beefyVault = IBeefyVault(0x42ECfA11Db08FB3Bb0AAf722857be56FA8E57Dc0);
    IPair public tusdPair = IPair(0x12692B3bf8dd9Aa1d2E721d1a79efD0C244d7d96);
    IVToken public iToken = IVToken(0x789B5DBd47d7Ca3799f8E9FdcE01bC5E356fcDF1);
    IBalancerVault public balancerVault = IBalancerVault(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);

    event VaultOwnershipChanged(address oldOwner, address newOwner);

    constructor() {
        // Approve tusd for spend by iToken
        tusd.safeApprove(address(iToken), type(uint).max);
    }

    // Vault Balance - Balance of TUSD in the iToken address is amount needed to withdraw fully.
    function tusdNeeded() public view returns (uint256) {
        return beefyVault.balance() - tusd.balanceOf(address(iToken));
    }

    // We can grab the total fee
    function getTotalFlashFee() public view returns (uint256) {
        return getSpookyFlashFee(tusdNeeded() - 100000000000000000000000) + getBalancerFeeAmount(100000000000000000000000);
    }

    // We can grab the total fee as .002 / .998 since Spooky charges 2% fees.
    function getSpookyFlashFee(uint256 _tusdNeeded) public pure returns (uint256) {
        return (_tusdNeeded * 0.0020040080160321 ether) / 1 ether;
    }

    function getBalancerFeeAmount(uint256 _amount) public pure returns (uint256) {
        uint256 product = _amount * 300000000000000; 
        return ((product - 1) / 1e18) + 1;
        }

    // Flash Loan the difference needed, preform upgrade and return funds plus fee
    function upgrade() external onlyOwner {
        // Update Balances to ensure we grab the correct amount needed
        IStrategy(beefyVault.strategy()).updateBalance();
        // Transfer the flash fee from msg.sender
        tusd.safeTransferFrom(msg.sender, address(this), getTotalFlashFee());
        // Start Flash Loan

        address[] memory tokens = new address[](1);
        tokens[0] = address(tusd);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100000000000000000000000;
        balancerVault.flashLoan(address(this), tokens, amounts, "BeefyBalancerFlash");
    }

    // Finish FlashSwap & Upgrade
    function uniswapV2Call(address, uint, uint amount1, bytes calldata) external {
        require(msg.sender == address(tusdPair), "!pair");
        
        // Supply collateral with loaned amount + fee, upgrade and withdraw collateral
        iToken.mint(tusd.balanceOf(address(this)));
        beefyVault.upgradeStrat();
        iToken.redeem(IERC20(address(iToken)).balanceOf(address(this)));

        // Pay our debts (Flash Loan capital + Fee)
        uint256 debt = amount1 + getSpookyFlashFee(amount1);
        tusd.safeTransfer(address(tusdPair), debt);
    }

    function receiveFlashLoan(address[] memory, uint256[] memory amounts, uint256[] memory feeAmounts, bytes memory) external {
        tusdPair.swap(0, tusdNeeded() - amounts[0], address(this), "BeefyRescue");
        uint256 balancerDebt = amounts[0] + feeAmounts[0];
        tusd.safeTransfer(address(balancerVault), balancerDebt);
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