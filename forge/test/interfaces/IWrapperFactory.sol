// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0 <0.9.0;

interface IWrapperFactory {
    function clone(address _vault) external returns (address proxy);
}