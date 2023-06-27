// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/curve/IConic.sol";
import "../../zaps/zapInterfaces/IBeefyVault.sol";
import "../../zaps/zapInterfaces/IWETH.sol";

interface IBeefyStrategy {
    function withdrawFee() external view returns (uint256);
    function WITHDRAWAL_MAX() external view returns (uint256);
}

contract ConicZap {
    using SafeERC20 for IERC20;
    using SafeERC20 for IBeefyVault;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CNC = 0x9aE380F0272E2162340a5bB646c354271c0F5cFC;
    uint256 public constant minimumAmount = 1000;

    receive() external payable {
        assert(msg.sender == WETH);
    }

    function estimateSwap(IBeefyVault beefyVault, address tokenIn, uint256 fullInvestmentIn) public view returns (uint256 swapAmountIn, uint256 swapAmountOut, address swapTokenOut) {
        (address lpToken, IConicPool conicPool) = _getVaultPool(beefyVault);

        require(conicPool.underlying() == tokenIn, 'Beefy: Input token not present in pool');

        swapTokenOut = lpToken;
        swapAmountIn = fullInvestmentIn;
        swapAmountOut = fullInvestmentIn * 1e18 / conicPool.exchangeRate();
    }

    function beefInETH(IBeefyVault beefyVault, uint256 tokenAmountOutMin) external payable {
        require(msg.value >= minimumAmount, 'Beefy: Insignificant input amount');

        IWETH(WETH).deposit{value: msg.value}();

        _depositAndStake(beefyVault, tokenAmountOutMin, WETH);
    }

    function beefIn (IBeefyVault beefyVault, uint256 tokenAmountOutMin, address tokenIn, uint256 tokenInAmount) external {
        require(tokenInAmount >= minimumAmount, 'Beefy: Insignificant input amount');
        require(IERC20(tokenIn).allowance(msg.sender, address(this)) >= tokenInAmount, 'Beefy: Input token is not approved');

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), tokenInAmount);

        _depositAndStake(beefyVault, tokenAmountOutMin, tokenIn);
    }

    function _depositAndStake(IBeefyVault beefyVault, uint256 tokenAmountOutMin, address tokenIn) private {
        (address lpToken, IConicPool conicPool) = _getVaultPool(beefyVault);

        require(conicPool.underlying() == tokenIn, 'Beefy: Input token not present in pool');

        uint256 fullInvestment = _balanceOfThis(tokenIn);
        _approveTokenIfNeeded(tokenIn, address(conicPool));
        conicPool.deposit(fullInvestment, tokenAmountOutMin, false);

        _approveTokenIfNeeded(lpToken, address(beefyVault));
        beefyVault.deposit(_balanceOfThis(lpToken));

        beefyVault.safeTransfer(msg.sender, _balanceOfThis(address(beefyVault)));
        _returnAssets(tokenIn);
    }

    function estimateSwapOut(IBeefyVault beefyVault, address desiredToken, uint256 withdrawAmount) public view returns (uint256 swapAmountIn, uint256 swapAmountOut, address swapTokenIn) {
        (address lpToken, IConicPool conicPool) = _getVaultPool(beefyVault);

        require(conicPool.underlying() == desiredToken, 'Beefy: desired token not present in pool');

        IBeefyStrategy strategy = IBeefyStrategy(beefyVault.strategy());
        uint withdrawWantAmount = withdrawAmount * beefyVault.balance() / beefyVault.totalSupply();
        uint withdrawalFeeAmount = withdrawWantAmount * strategy.withdrawFee() / strategy.WITHDRAWAL_MAX();
        withdrawWantAmount = withdrawWantAmount - withdrawalFeeAmount;

        swapAmountIn = withdrawWantAmount;
        swapTokenIn = lpToken;
        swapAmountOut = swapAmountIn * conicPool.exchangeRate() / 1e18;
    }

    function beefOutAndSwap(IBeefyVault beefyVault, uint256 withdrawAmount, address desiredToken, uint256 desiredTokenOutMin) external {
        (address lpToken, IConicPool conicPool) = _getVaultPool(beefyVault);

        require(conicPool.underlying() == desiredToken, 'Beefy: desired token not present in pool');

        beefyVault.safeTransferFrom(msg.sender, address(this), withdrawAmount);
        beefyVault.withdraw(withdrawAmount);
        conicPool.withdraw(_balanceOfThis(lpToken), desiredTokenOutMin);

        _returnAssets(desiredToken);
    }

    function _getVaultPool(IBeefyVault beefyVault) private view returns (address lpToken, IConicPool conicPool) {
        lpToken = beefyVault.want();
        conicPool = IConicPool(ILpToken(lpToken).minter());
    }

    function _returnAssets(address underlying) private {
        uint256 balance = _balanceOfThis(underlying);
        if (balance > 0) {
            if (underlying == WETH) {
                IWETH(WETH).withdraw(balance);
                (bool success,) = msg.sender.call{value: balance}(new bytes(0));
                require(success, 'Beefy: ETH transfer failed');
            } else {
                IERC20(underlying).safeTransfer(msg.sender, balance);
            }
        }

        // CNC rebalancing reward
        balance = _balanceOfThis(CNC);
        if (balance > 0) {
            IERC20(CNC).safeTransfer(msg.sender, balance);
        }
    }

    function _approveTokenIfNeeded(address token, address spender) private {
        if (IERC20(token).allowance(address(this), spender) == 0) {
            IERC20(token).safeApprove(spender, type(uint256).max);
        }
    }

    function _balanceOfThis(address _token) private view returns (uint) {
        return IERC20(_token).balanceOf(address(this));
    }

}