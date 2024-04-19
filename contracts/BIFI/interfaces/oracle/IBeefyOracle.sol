// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IBeefyOracle {
    function getPrice(address token) external view returns (uint256 price);
    
    function getFreshPrice(address token) external returns (uint256 price, bool success);

    function getPrice(address caller, address token) external view returns (uint256 price);

    function getFreshPrice(
        address caller,
        address token
    ) external returns (uint256 price, bool success);

    function setOracles(
        address[] calldata _tokens,
        address[] calldata _oracles,
        bytes[] calldata _datas
    ) external;
}
