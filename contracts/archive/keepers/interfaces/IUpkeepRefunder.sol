// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

interface IUpkeepRefunder {
    event SwappedNativeToLink(uint256 indexed blockNumber, uint256 nativeAmount, uint256 linkAmount);

    function notifyRefundUpkeep() external returns (uint256 linkRefunded_);
}
