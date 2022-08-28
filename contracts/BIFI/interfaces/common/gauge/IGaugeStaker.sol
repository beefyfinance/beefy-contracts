// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IGaugeStaker {
    function vote(address[] calldata _tokenVote, uint256[] calldata _weights) external;
    function depositAll() external;
    function deposit(uint256 _amount) external;
    function depositFor(address _user, uint256 _amount) external;
    function increaseUnlockTime() external;
    function currentUnlockTime() external view returns (uint256);
    function balanceOfWant() external view returns (uint256);
    function balanceOfVe() external view returns (uint256);
    function deposit(address _gauge, uint256 _amount) external;
    function withdraw(address _gauge, uint256 _amount) external;
    function withdrawAll(address _gauge) external;
    function claimGaugeReward(address _gauge) external;
    function claimVeWantReward() external;
    function upgradeStrategy(address _gauge) external;
}
