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

interface IConvexRewardPool {
    function balanceOf(address account) external view returns (uint256);
    function earned(address account) external view returns (uint256);
    function periodFinish() external view returns (uint256);
    function getReward() external;
    function getReward(address _account, bool _claimExtras) external;
    function withdrawAndUnwrap(uint256 _amount, bool claim) external;
    function withdrawAllAndUnwrap(bool claim) external;
}