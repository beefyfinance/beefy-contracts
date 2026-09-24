// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20MetadataUpgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import { IBalancerVault } from "../../interfaces/beethovenx/IBalancerVault.sol";
import { BeefyOracleHelper, IBeefyOracle, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

/// @title Beefy Oracle for Balancer
/// @author Beefy, @weso
/// @notice On-chain oracle using Balancer
contract BeefyOracleBalancer {

    struct BatchSwapStruct {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
    }

    IBalancerVault.SwapKind public swapKind = IBalancerVault.SwapKind.GIVEN_IN;
    IBalancerVault.FundManagement public funds = IBalancerVault.FundManagement(address(this), false, payable(address(this)), false);
    IBalancerVault vault = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    /// @notice Fetch price from the QueryBatchSwap on Balancer Vault
    /// @param _data Payload which require swap steps and assets
    /// @return price Retrieved price from the chained quotes
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external returns (uint256 price, bool success) {
        (BatchSwapStruct[] memory swaps, address[] memory assets) = 
            abi.decode(_data, (BatchSwapStruct[], address[]));

        IBalancerVault.BatchSwapStep[] memory swapsArray = buildSwapStructArray(swaps, IERC20MetadataUpgradeable(assets[0]).decimals());

        (bool ok, bytes memory result) = address(vault).call(abi.encodeWithSelector(0xf84d066e, swapKind, swapsArray, assets, funds));
        require (!ok);

        int256[] memory endResults = abi.decode(result, (int256[]));

        uint256 amountOut = uint256(endResults[endResults.length - 1]);

        price = BeefyOracleHelper.priceFromBaseToken(
            msg.sender, assets[assets.length - 1], assets[0], amountOut
        );
        if (price != 0) success = true;
    }

    function buildSwapStructArray(BatchSwapStruct[] memory _route, uint256 _amountIn) internal pure returns (IBalancerVault.BatchSwapStep[] memory) {
        IBalancerVault.BatchSwapStep[] memory swaps = new IBalancerVault.BatchSwapStep[](_route.length);
        for (uint i; i < _route.length;) {
            if (i == 0) {
                swaps[0] =
                    IBalancerVault.BatchSwapStep({
                        poolId: _route[0].poolId,
                        assetInIndex: _route[0].assetInIndex,
                        assetOutIndex: _route[0].assetOutIndex,
                        amount: _amountIn,
                        userData: ""
                    });
            } else {
                swaps[i] =
                    IBalancerVault.BatchSwapStep({
                        poolId: _route[i].poolId,
                        assetInIndex: _route[i].assetInIndex,
                        assetOutIndex: _route[i].assetOutIndex,
                        amount: 0,
                        userData: ""
                    });
            }
            unchecked {
                ++i;
            }
        }

        return swaps;
    }


    /// @notice Data validation for new oracle data being added to central oracle
    /// @param _data Encoded addresses of the token route
    function validateData(bytes calldata _data) external view {
        (BatchSwapStruct[] memory swaps, address[] memory assets) = 
            abi.decode(_data, (BatchSwapStruct[], address[]));
        
        uint256 basePrice = IBeefyOracle(msg.sender).getPrice(assets[0]);
        if (basePrice == 0) revert BeefyOracleErrors.NoBasePrice(assets[0]);

        swaps = swaps;
    }
}