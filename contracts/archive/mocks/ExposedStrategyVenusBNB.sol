// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "../strategies/Venus/StrategyVenusBNB.sol";

contract ExposedStrategyVenusBNB is StrategyVenusBNB {
    constructor(
        address _vault, 
        uint256 _borrowRate, 
        uint256 _borrowDepth, 
        address[] memory _markets
    ) StrategyVenusBNB(
        _vault, 
        _borrowRate,
        _borrowDepth,
        _markets
    ) public {}

    function leverage(uint256 _amount) public  {
        _leverage(_amount);
    }   

    function deleverage() public  {
        _deleverage();
    } 
}