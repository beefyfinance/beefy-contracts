// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISiloV2 {
    function deposit(uint256 _assets, address _receiver) external;
    function withdraw(uint256 _assets, address _receiver, address _owner) external;
    function redeem(uint256 _shares, address _receiver, address _owner) external returns (uint256 assets);
    function convertToAssets(uint256 _shares) external view returns (uint256);
    function balanceOf(address _who) external view returns (uint256);
}
