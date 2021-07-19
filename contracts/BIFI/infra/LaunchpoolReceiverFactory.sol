// SPDX-License-Identifier: MIT

pragma solidity ^0.5.0;

import "@openzeppelin-2/contracts/ownership/Ownable.sol";

import "./BeefyLaunchpoolReceiver.sol";

contract LaunchpoolReceiverFactory is Ownable {

    address public defaultDev = address(0x982F264ce97365864181df65dF4931C593A515ad);
    uint256 public fee = 50;

    event ReceiverCreated(address receiver);

    function createReceiver(address token) external returns (address) {
        BeefyLaunchpoolReceiver receiver = new BeefyLaunchpoolReceiver(msg.sender, defaultDev, token, fee);
        receiver.transferOwnership(owner());
        emit ReceiverCreated(address(receiver));
        return address(receiver);
    }

    function setDefaultDev(address _dev) external onlyOwner {
        defaultDev = _dev;
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

}
