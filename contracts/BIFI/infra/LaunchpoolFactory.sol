// SPDX-License-Identifier: MIT

pragma solidity ^0.5.0;

import "@openzeppelin-2/contracts/ownership/Ownable.sol";

import "./BeefyLaunchpool.sol";

interface ILaunchpoolReceiverFactory {
    function owner() external view returns (address);
    function createReceiver(address token) external returns (address);
}

contract LaunchpoolFactory is Ownable {

    ILaunchpoolReceiverFactory public receiverFactory;

    event ReceiverCreated(address receiver);
    event LaunchpoolCreated(address launchpool);

    function createReceiver(address token) external {
        address receiver = receiverFactory.createReceiver(token);
        emit ReceiverCreated(receiver);
    }

    function createLaunchpool(address _stakedToken, address _rewardToken, uint256 _durationDays) external {
        uint256 duration = 3600 * 24 * _durationDays;
        BeefyLaunchpool launchpool = new BeefyLaunchpool(_stakedToken, _rewardToken, duration);
        launchpool.transferOwnership(owner());
        emit LaunchpoolCreated(address(launchpool));
    }

    function setReceiverFactory(ILaunchpoolReceiverFactory _factory) external onlyOwner {
        require(owner() == _factory.owner(), "wrong owner");
        receiverFactory = _factory;
    }
}
