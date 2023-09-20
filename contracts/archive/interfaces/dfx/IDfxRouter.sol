// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IDfxRouter {
    function originSwap(
        address _quoteCurrency,
        address _origin,
        address _target,
        uint256 _originAmount,
        uint256 _minTargetAmount,
        uint256 _deadline
    ) external returns (uint256 _targetAmount);

    function viewOriginSwap(
        address _quoteCurrency,
        address _origin,
        address _target,
        uint256 _originAmount
    ) external view returns (uint256 _targetAmount);
}
