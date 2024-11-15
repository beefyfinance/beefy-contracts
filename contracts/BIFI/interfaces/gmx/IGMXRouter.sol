// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGMXRouter {
    function stakeGmx(uint256 amount) external;
    function unstakeGmx(uint256 amount) external;
    function compound() external;
    function claimFees() external;
    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);
    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;
    function feeGlpTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);
    function stakedGmxTracker() external view returns (address);
    function glpManager() external view returns (address);
    function glp() external view returns (address);
    function gmx() external view returns (address);
    function signalTransfer(address _receiver) external;
    function acceptTransfer(address _sender) external;
}
