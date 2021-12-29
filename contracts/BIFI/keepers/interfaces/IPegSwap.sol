// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

interface IPegSwap {
    event LiquidityUpdated(uint256 amount, address indexed source, address indexed target);
    event OwnershipTransferRequested(address indexed from, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);
    event StuckTokensRecovered(uint256 amount, address indexed target);
    event TokensSwapped(uint256 amount, address indexed source, address indexed target, address indexed caller);

    /* solhint-disable payable-fallback */
    fallback() external;

    /* solhint-enable payable-fallback */

    function acceptOwnership() external;

    function addLiquidity(
        uint256 amount,
        address source,
        address target
    ) external;

    function getSwappableAmount(address source, address target) external view returns (uint256 amount);

    function onTokenTransfer(
        address sender,
        uint256 amount,
        bytes memory targetData
    ) external;

    function owner() external view returns (address);

    function recoverStuckTokens(uint256 amount, address target) external;

    function removeLiquidity(
        uint256 amount,
        address source,
        address target
    ) external;

    function swap(
        uint256 amount,
        address source,
        address target
    ) external;

    function transferOwnership(address _to) external;
}
