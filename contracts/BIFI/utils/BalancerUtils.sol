// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/beethovenx/IBalancerVault.sol";

library BalancerUtils {
    struct SingleSwapInfo {
        IBalancerVault.SingleSwap singleSwap;
        IBalancerVault.FundManagement funds;
    }

    struct BatchSwapInfo {
        IBalancerVault.SwapKind swapKind;
        IBalancerVault.BatchSwapStep[] swaps;
        address[] route;
        IBalancerVault.FundManagement funds;
        int[] limits;
    }

    /**
     * @dev Swap using a single pool with a custom pool and route.
     * @param _router Address of the router to make the swap.
     * @param _pool Hash of the pool which contains the two tokens to swap between.
     * @param _route Addresses of the tokens in the order of swapping.
     * @param _amountIn Amount of the input token to use in the swap.
     * @return amountCalculated The amount of the output token resulting from the swap.
     */
    function swap(
        IBalancerVault _router,
        bytes32 _pool,
        address[] calldata _route,
        uint _amountIn
    ) internal returns (uint) {
        SingleSwapInfo memory swapInfo = getSwapInfo(_pool, _route);
        return swap(_router, swapInfo, _amountIn);
    }

    /**
     * @dev Swap using a single pool with set parameters.
     * @param _router Address of the router to make the swap.
     * @param _swapInfo Pre-determined struct data used to make the swap.
     * @param _amountIn Amount of the input token to use in the swap.
     * @return amountCalculated The amount of the output token resulting from the swap.
     */
    function swap(
        IBalancerVault _router,
        SingleSwapInfo memory _swapInfo,
        uint _amountIn
    ) internal returns (uint) {
        _swapInfo.singleSwap.amount = _amountIn;
        return IBalancerVault(_router).swap(_swapInfo.singleSwap, _swapInfo.funds, 1, block.timestamp);
    }

    /**
     * @dev Swap using multiple pools with custom pools and route.
     * @param _router Address of the router to make the swap.
     * @param _pools Hashes of the pools which contains the tokens to swap between.
     * @param _route Addresses of the tokens in the order of swapping.
     * @param _amountIn Amount of the input token to use in the swap.
     * @return deltaAmounts The signed amount of the token changes occuring in the swap.
     */
    function swap(
        IBalancerVault _router,
        bytes32[] memory _pools,
        address[] memory _route,
        uint _amountIn
    ) internal returns (int[] memory) {
        BatchSwapInfo memory swapInfo = getBatchSwapInfo(_pools, _route);
        swapInfo.swaps[0].amount = _amountIn;
        return IBalancerVault(_router).batchSwap(
            swapInfo.swapKind,
            swapInfo.swaps,
            swapInfo.route,
            swapInfo.funds,
            swapInfo.limits,
            block.timestamp
        );
    }

    /**
     * @dev Swap using multiple pools with set parameters.
     * @param _router Address of the router to make the swap.
     * @param _swapInfo Pre-determined struct data used to make the swap.
     * @param _amountIn Amount of the input token to use in the swap.
     * @return deltaAmounts The signed amount of the token changes occuring in the swap.
     */
    function swap(
        IBalancerVault _router,
        BatchSwapInfo memory _swapInfo,
        uint _amountIn
    ) internal returns (int[] memory) {
        _swapInfo.swaps[0].amount = _amountIn;
        return IBalancerVault(_router).batchSwap(
            _swapInfo.swapKind,
            _swapInfo.swaps,
            _swapInfo.route,
            _swapInfo.funds,
            _swapInfo.limits,
            block.timestamp
        );
    }

    /**
     * @dev Calculate the parameters for a specific swap using a one pool.
     * @param _pool Hash of the pool which contains the two tokens to swap between.
     * @param _route Addresses of the tokens in the order of swapping.
     * @return swapInfo Data used to make the swap for a single pool.
     */
    function getSwapInfo(
        bytes32 _pool,
        address[] calldata _route
    ) internal view returns (SingleSwapInfo memory swapInfo) {
        IBalancerVault.SingleSwap memory singleSwap = IBalancerVault.SingleSwap(
            _pool,
            swapKind(),
            _route[0],
            _route[1],
            0,
            ""
        );
        swapInfo = SingleSwapInfo(singleSwap, funds());
    }

    /**
     * @dev Calculate the parameters for a specific swap using multiple pools.
     * @param _pools Hashes of the pools which contain the tokens to swap between.
     * @param _route Addresses of the tokens in the order of swapping.
     * @return swapInfo Data used to make a multi-hop swap.
     */
    function getBatchSwapInfo(
        bytes32[] memory _pools,
        address[] memory _route
    ) internal view returns (BatchSwapInfo memory swapInfo) {
        IBalancerVault.BatchSwapStep[] memory swaps;
        uint poolLength = _pools.length;
        for (uint i; i < poolLength;) {
            swaps[i] = IBalancerVault.BatchSwapStep(_pools[i], i, i+1, 0, "");
            unchecked { ++i; }
        }
        swapInfo = BatchSwapInfo(
            swapKind(),
            swaps,
            _route,
            funds(),
            limits(_route.length)
        );
    }

    /**
     * @dev Add liquidity to a balancer pool.
     * @param _router Address of the router.
     * @param _poolId Hash of the pool to add liquidity to.
     * @param _input Address of the token being deposited to the pool. 
     * @param _amountIn Amount of the input token to add to the pool.
     */
    function addLiquidity(
        address _router,
        bytes32 _poolId,
        address _input,
        uint _amountIn
    ) internal {
        (address[] memory lpTokens,,) = IBalancerVault(_router).getPoolTokens(_poolId);
        uint tokenLength = lpTokens.length;
        uint[] memory amounts = new uint[](tokenLength);
        for (uint i; i < tokenLength;) {
            amounts[i] = lpTokens[i] == _input ? _amountIn : 0;
            unchecked { ++i; }
        }
        bytes memory userData = abi.encode(1, amounts, 1);

        IBalancerVault.JoinPoolRequest memory request = IBalancerVault.JoinPoolRequest(
            lpTokens,
            amounts,
            userData,
            false
        );
        IBalancerVault(_router).joinPool(_poolId, address(this), address(this), request);
    }

    /**
     * @dev Estimate the outputs of a swap with custom pools and routes.
     * @param _router Address of the router.
     * @param _pools Hashes of the pools to check the swap amount from.
     * @param _route Addresses of the tokens being swapped in order. 
     * @param _amountIn Amount of the input token to swap.
     * @return amounts Amounts of tokens being output from each swap step.
     */
    function getAmountsOut(
        IBalancerVault _router,
        bytes32[] calldata _pools,
        address[] calldata _route,
        uint _amountIn
    ) internal view returns (uint[] memory) {
        uint poolLength = _pools.length;
        uint[] memory amounts = new uint[](poolLength+1);
        amounts[0] = _amountIn;
        for (uint i; i < poolLength;) {
            amounts[i+1] = getAmountOut(_router, _pools[i], _route[i], _route[i+1], amounts[i]);
            unchecked { ++i; }
        }
        return amounts;
    }

    /**
     * @dev Estimate the outputs of a multi-hop swap with set parameters.
     * @param _router Address of the router.
     * @param _swapInfo Pre-determined struct data used to make a multi-pool swap.
     * @param _amountIn Amount of the input token to swap.
     * @return amounts Amounts of tokens being output from each swap step.
     */
    function getAmountsOut(
        IBalancerVault _router,
        BatchSwapInfo memory _swapInfo,
        uint _amountIn
    ) internal view returns (uint[] memory) {
        uint swapLength = _swapInfo.swaps.length;
        uint[] memory amounts = new uint[](swapLength+1);
        amounts[0] = _amountIn;
        for (uint i; i < swapLength;) {
            amounts[i+1] = getAmountOut(
                _router,
                _swapInfo.swaps[i].poolId,
                _swapInfo.route[i],
                _swapInfo.route[i+1],
                amounts[i]
            );
            unchecked { ++i; }
        }
        return amounts;
    }

    /**
     * @dev Estimate the output of a single swap with custom pool and route.
     * @param _router Address of the router.
     * @param _swapInfo Pre-determined struct data used to make a single swap.
     * @param _amountIn Amount of the input token to swap.
     * @return amount Amount being output from the swap.
     */
    function getAmountOut(
        IBalancerVault _router,
        SingleSwapInfo memory _swapInfo,
        uint _amountIn
    ) internal view returns (uint) {
        return getAmountOut(
            _router,
            _swapInfo.singleSwap.poolId,
            _swapInfo.singleSwap.assetIn,
            _swapInfo.singleSwap.assetOut,
            _amountIn
        );
    }

    /**
     * @dev Estimate the output of a single swap with custom pool and route.
     * @param _router Address of the router.
     * @param _pool Hash of the pool to check the swap amount from.
     * @param _tokenIn Address of the input token being swapped.
     * @param _tokenIn Address of the output token being received.
     * @param _amountIn Amount of the input token to swap.
     * @return amount Amount being output from the swap.
     */
    function getAmountOut(
        IBalancerVault _router,
        bytes32 _pool,
        address _tokenIn,
        address _tokenOut,
        uint _amountIn
    ) internal view returns (uint) {
        uint reserveA;
        uint reserveB;
        (address[] memory tokens, uint[] memory balances,) = 
            IBalancerVault(_router).getPoolTokens(_pool);
        for (uint i; i < tokens.length;) {
            if (tokens[i] == _tokenIn) {
                reserveA = balances[i];
            } else if (tokens[i] == _tokenOut) {
                reserveB = balances[i];
            }
            unchecked { ++i; }
        }
        return _amountIn * reserveB / (reserveA + _amountIn);
    }

    /**
     * @dev Calculate and assign the parameters for a specific swap using multiple pools. Assigning
     * is done here to work around the limitation of copying a memory struct arrary into storage.
     * @param _storedInfo Pointer to assign the swap info to.
     * @param _pools Hashes of the pools which contain the tokens to swap between.
     * @param _route Addresses of the tokens in the order of swapping.
     */
    function assignBatchSwapInfo(
        BatchSwapInfo storage _storedInfo,
        bytes32[] memory _pools,
        address[] memory _route
    ) internal {
        uint poolLength = _pools.length;
        for (uint i; i < poolLength;) {
            _storedInfo.swaps.push(IBalancerVault.BatchSwapStep(_pools[i], i, i+1, 0, ""));
            unchecked { ++i; }
        }
        _storedInfo.swapKind = swapKind();
        _storedInfo.route = _route;
        _storedInfo.funds = funds();
        _storedInfo.limits = limits(_route.length);
    }

    /**
     * @dev Return the swap kind, not stored here due to library restrictions.
     * @return swapkind Enum is always GIVEN_IN.
     */
    function swapKind() private pure returns (IBalancerVault.SwapKind) {
        return IBalancerVault.SwapKind.GIVEN_IN;
    }

    /**
     * @dev Return a completed fund management struct, not stored here due to library restrictions.
     * @return funds Struct is always the same with receiver address the same as sender.
     */
    function funds() private view returns (IBalancerVault.FundManagement memory) {
        return IBalancerVault.FundManagement(
            address(this),
            false,
            payable(address(this)),
            false
        );
    }

    /**
     * @dev Create an array of minimum amounts to receive from swaps.
     * @return limit Uint array initialized with the value of 1.
     */
    function limits(uint _length) private pure returns (int[] memory) {
        int[] memory limit = new int[](_length);
        limit[0] = type(int).max;
        for (uint i = 1; i < _length;) {
            limit[i] = int(0);
            unchecked { ++i; }
        }
        return limit;
    }
}
