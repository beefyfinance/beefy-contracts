// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-5/contracts/interfaces/IERC4626.sol";
import "@openzeppelin-5/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BeefyERC4626Unwrapper
/// @author Beefy, kexley
/// @notice A contract for unwrapping ERC4626 tokens
contract BeefyERC4626Unwrapper {
    using SafeERC20 for IERC4626;

    /// @notice Unwraps an amount of ERC4626 tokens
    /// @param _erc4626 The ERC4626 token to unwrap
    /// @param _amount The amount of ERC4626 tokens to unwrap
    /// @param _minAmountOut The minimum amount of underlying tokens to receive
    function unwrap(IERC4626 _erc4626, uint256 _amount, uint256 _minAmountOut) external {
        _erc4626.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 redeemed = _erc4626.redeem(_amount, msg.sender, address(this));
        require(redeemed >= _minAmountOut, "<minAmountOut");
    }
}
