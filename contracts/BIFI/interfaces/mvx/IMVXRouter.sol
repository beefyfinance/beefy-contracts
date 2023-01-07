// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMVXRouter {
    function stakeMvx(uint256 amount) external;
    function unstakeMvx(uint256 amount) external;
    function compound() external;
    function claimFees() external;
    function mintAndStakeMvlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);
    function unstakeAndRedeemMvlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    ) external returns (uint256);
    function feeMvlpTracker() external view returns (address);
    function feeMvxTracker() external view returns (address);
    function stakedMvxTracker() external view returns (address);
    function mvlpManager() external view returns (address);
    function mvlp() external view returns (address);
    function signalTransfer(address _receiver) external;
    function acceptTransfer(address _sender) external;
}
