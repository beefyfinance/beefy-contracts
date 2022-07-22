// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IBentoBox {
    function setMasterContractApproval(
        address user,
        address masterContract,
        bool approved,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}