// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../infra/BeefyOracle/BeefyOracleHelper.sol";
import "@openzeppelin-4/contracts/interfaces/IERC4626.sol";

/// @title BeefyOracleERC4626
/// @author Beefy, kexley
/// @notice Oracle for ERC4626 vaults
contract BeefyOracleERC4626 {
    /// @notice Gets the price of the ERC4626 vault
    /// @param _data The data encoded with the vault address
    /// @return price The price of the ERC4626 vault
    /// @return success Whether the price was successfully retrieved
    function getPrice(bytes calldata _data) external returns (uint256 price, bool success) {
        (address vault) = abi.decode(_data, (address));
        address asset = IERC4626(vault).asset();
        uint amountOut = IERC4626(vault).convertToShares(10 ** IERC4626(vault).decimals());
        price = BeefyOracleHelper.priceFromBaseToken(msg.sender, vault, asset, amountOut);
        return (price, true);
    }

    /// @notice Validates the data
    /// @param _data The data encoded with the vault address
    function validateData(bytes calldata _data) external view {
        (address vault) = abi.decode(_data, (address));
        address asset = IERC4626(vault).asset();
        uint amountOut = IERC4626(vault).convertToShares(10 ** IERC4626(vault).decimals());
        if (vault == address(0) || asset == address(0) || amountOut == 0) revert BeefyOracleErrors.NoAnswer();
        if (IBeefyOracle(msg.sender).getPrice(asset) == 0) revert BeefyOracleErrors.NoBasePrice(asset);
    }
}