// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IQlpRouter {
    function handleRewards(
        bool _shouldConvertWethToEth,
        bool _shouldAddIntoQLP
    ) external;

    function mintAndStakeQlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdq,
        uint256 _minQlp
    ) external returns (uint256);
    
    function feeQlpTracker() external view returns (address);

    function qlpManager() external view returns (address);
    
    function signalTransfer(address _receiver) external;

    function acceptTransfer(address _sender) external;
}
