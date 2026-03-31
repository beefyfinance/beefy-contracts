// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStrategyConcLiq {
    function balances() external view returns (uint256, uint256);
    function balancesOfPool() external view returns (uint256 token0Bal, uint256 token1Bal, uint256 mainAmount0, uint256 mainAmount1, uint256 altAmount0, uint256 altAmount1);
    function beforeAction() external;
    function deposit() external;
    function harvest() external;
    function panic(uint256 _minAmount0, uint256 _minAmount1) external;
    function withdraw(uint256 _amount0, uint256 _amount1) external;
    function setPositionWidth(int24 _width) external;
    function pool() external view returns (address);
    function lpToken0() external view returns (address);
    function lpToken1() external view returns (address);
    function isCalm() external view returns (bool);
    function swapFee() external view returns (uint256);

    /// @notice The current price of the pool in token1, encoded with `36 + lpToken1.decimals - lpToken0.decimals`.
    /// @return _price The current price of the pool in token1.
    function price() external view returns (uint256 _price);

    function positionWidth() external view returns (int24);
    function maxTickDeviation() external view returns (int56);
    function twapInterval() external view returns (uint32);
    function range() external view returns (uint, uint);

}