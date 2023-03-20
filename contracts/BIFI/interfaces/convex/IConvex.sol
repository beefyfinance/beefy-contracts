// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.9.0;

interface IConvexBooster {
    function deposit(uint256 pid, uint256 amount, bool stake) external returns (bool);
    function earmarkRewards(uint256 _pid) external;
    function poolInfo(uint256 pid) external view returns (
        address lptoken,
        address token,
        address gauge,
        address crvRewards,
        address stash,
        bool shutdown
    );
}

interface IConvexBoosterL2 {
    function deposit(uint256 _pid, uint256 _amount) external returns (bool);
    function poolInfo(uint256 pid) external view returns (
        address lptoken, //the curve lp token
        address gauge, //the curve gauge
        address rewards, //the main reward/staking contract
        bool shutdown, //is this pool shutdown?
        address factory //a reference to the curve factory used to create this pool (needed for minting crv)
    );
}

interface IConvexRewardPool {
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function periodFinish() external view returns (uint256);
    function getReward() external;
    function getReward(address _account, bool _claimExtras) external;
    function getReward(address _account) external;
    function withdrawAndUnwrap(uint256 _amount, bool claim) external;
    function withdrawAllAndUnwrap(bool claim) external;

    // L2 interface
    function withdraw(uint256 _amount, bool _claim) external;
    function emergencyWithdraw(uint256 _amount) external;
}