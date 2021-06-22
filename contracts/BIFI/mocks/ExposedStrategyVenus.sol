// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "../strategies/Venus/StrategyVenus.sol";

contract ExposedStrategyVenus is StrategyVenus {
    constructor(
        address _vault, 
        address _vtoken,
        uint256 _borrowRate, 
        uint256 _borrowDepth, 
        uint256 _minLeverage,
        address[] memory _markets
    ) StrategyVenus(
        _vault,
        _vtoken, 
        _borrowRate,
        _borrowDepth,
        _minLeverage,
        _markets
    ) public {}

    function leverage(uint256 _amount) public  {
        _leverage(_amount);
    }   

    function deleverage() public  {
        _deleverage();
    } 
}