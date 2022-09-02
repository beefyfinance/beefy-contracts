// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin-4/contracts/access/Ownable.sol";

contract BeefyPairFeeDataSource is Ownable {

    struct FeeData {
        uint256 rootKInteger;
        uint256 rootKLastInteger;
    }

    // Map the FeeData by Factory 
    mapping (address => FeeData) public feeData;
    mapping (address => bool) public isSolidPair;
    function setUpAFactory(address _factory, uint256 _rootKInteger, uint256 _rootKLastInteger) external onlyOwner {
        feeData[_factory].rootKInteger = _rootKInteger;
        feeData[_factory].rootKLastInteger = _rootKLastInteger;
    }

    function setUpASolidFactory(address _factory) external onlyOwner {
        isSolidPair[_factory] = true;
    }
}