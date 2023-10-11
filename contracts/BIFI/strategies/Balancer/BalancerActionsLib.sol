// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

import "@openzeppelin-4/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/beethovenx/IBalancerVault.sol";
import "./BeefyBalancerStructs.sol";

library BalancerActionsLib {
    function balancerJoin(address _vault, bytes32 _poolId, address _tokenIn, uint256 _amountIn) internal {
        (address[] memory lpTokens,,) = IBalancerVault(_vault).getPoolTokens(_poolId);
        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length;) {
            amounts[i] = lpTokens[i] == _tokenIn ? _amountIn : 0;
            unchecked { ++i; }
        }
        bytes memory userData = abi.encode(1, amounts, 1);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(lpTokens, amounts, userData, false);
        IBalancerVault(_vault).joinPool(_poolId, address(this), address(this), request);
    }

     function multiJoin(address _vault, address _want, bytes32 _poolId, address _token0In, address _token1In, uint256 _amount0In, uint256 _amount1In) internal {
        (address[] memory lpTokens,uint256[] memory balances,) = IBalancerVault(_vault).getPoolTokens(_poolId);
        uint256 supply = IERC20(_want).totalSupply();
        uint256[] memory amounts = new uint256[](lpTokens.length);
        for (uint256 i = 0; i < amounts.length;) {
            if (lpTokens[i] == _token0In) amounts[i] = _amount0In;
            else if (lpTokens[i] == _token1In) amounts[i] = _amount1In;
            else amounts[i] = 0;
            unchecked { ++i; }
        }

        uint256 bpt0 = (amounts[0] * supply / balances[0]) - 100;
        uint256 bpt1 = (amounts[1] * supply / balances[1]) - 100;

        uint256 bptOut = bpt0 > bpt1 ? bpt1 : bpt0;
        bytes memory userData = abi.encode(3, bptOut);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(lpTokens, amounts, userData, false);
        IBalancerVault(_vault).joinPool(_poolId, address(this), address(this), request);
    }

     function buildSwapStructArray(BeefyBalancerStructs.BatchSwapStruct[] memory _route, uint256 _amountIn) internal pure returns (IBalancerVault.BatchSwapStep[] memory) {
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

    function balancerSwap(address _vault, IBalancerVault.SwapKind _swapKind, IBalancerVault.BatchSwapStep[] memory _swaps, address[] memory _route, IBalancerVault.FundManagement memory _funds, int256 _amountIn) internal returns (int256[] memory) {
        int256[] memory limits = new int256[](_route.length);
        for (uint i; i < _route.length;) {
            if (i == 0) {
                limits[0] = _amountIn;
            } else if (i == _route.length - 1) {
                limits[i] = -1;
            }
            unchecked { ++i; }
        }
        return IBalancerVault(_vault).batchSwap(_swapKind, _swaps, _route, _funds, limits, block.timestamp);
    }
}