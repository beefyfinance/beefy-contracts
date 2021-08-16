// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "../Common/StrategyCommonChefLP.sol";
import "../../interfaces/common/IMasterChefGooseFork.sol";

contract StrategyGooseForkLP is StrategyCommonChefLP {

    constructor(
        address _want,
        uint256 _poolId,
        address _chef,
        address _vault,
        address _unirouter,
        address _keeper,
        address _strategist,
        address _beefyFeeRecipient,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route
    ) StrategyCommonChefLP(
        _want,
        _poolId,
        _chef,
        _vault,
        _unirouter,
        _keeper,
        _strategist,
        _beefyFeeRecipient,
        _outputToNativeRoute,
        _outputToLp0Route,
        _outputToLp1Route
    ) public {}

    function deposit() public override(StrategyCommonChefLP) {
        IMasterChefGooseFork.PoolInfo memory poolInfo = IMasterChefGooseFork(chef).poolInfo(poolId);
        require(poolInfo.depositFeeBP == 0, "Deposit fee too high");
        super.deposit();
    }
}
