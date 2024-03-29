// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFxnVoterProxy {
    function operator() external view returns (IFxBooster);
}

interface IPoolRegistry {
    function poolInfo(uint pid) external view returns (address impl, address gauge, address token, address rewards, uint8 active);
}

interface IFxBooster {
    function createVault(uint256 pid) external returns (address);
}

interface IConvexVault {
    function deposit(uint amount) external;
    function withdraw(uint amount) external;
    function getReward(bool claim) external;
    function getReward(bool claim, address[] calldata tokenList) external;
    function transferTokens(address[] calldata _tokenList) external;
    function execute(address _to,uint256 _value,bytes calldata _data) external returns (bool, bytes memory);
}