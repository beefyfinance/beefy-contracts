// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;
pragma experimental ABIEncoderV2;

interface IMiniChefV2 {
    event Deposit(address indexed user,uint256 indexed pid,uint256 amount,address indexed to);
    event EmergencyWithdraw(address indexed user,uint256 indexed pid,uint256 amount,address indexed to);
    event Harvest(address indexed user,uint256 indexed pid,uint256 amount);
    event LogPoolAddition(uint256 indexed pid,uint256 allocPoint,address indexed lpToken,address indexed rewarder);
    event LogSetPool(uint256 indexed pid,uint256 allocPoint,address indexed rewarder,bool overwrite);
    event LogSynapsePerSecond(uint256 synapsePerSecond);
    event LogUpdatePool(uint256 indexed pid,uint64 lastRewardTime,uint256 lpSupply,uint256 accSynapsePerShare);
    event OwnershipTransferred(address indexed previousOwner,address indexed newOwner);
    event Withdraw(address indexed user,uint256 indexed pid,uint256 amount,address indexed to);

    function SYNAPSE() external view returns (address);
    function add(uint256 allocPoint,address _lpToken,address _rewarder) external;
    function batch(bytes[] memory calls,bool revertOnFail) external payable returns (bool[] memory successes, bytes[] memory results);
    function claimOwnership() external;
    function deposit(uint256 pid,uint256 amount,address to) external;
    function emergencyWithdraw(uint256 pid,address to) external;
    function harvest(uint256 pid,address to) external;
    function lpToken(uint256) external view returns (address);
    function massUpdatePools(uint256[] memory pids) external;
    function owner() external view returns (address);
    function pendingOwner() external view returns (address);
    function pendingSynapse(uint256 _pid,address _user) external view returns (uint256 pending);
    function permitToken(address token,address from,address to,uint256 amount,uint256 deadline,uint8 v,bytes32 r,bytes32 s) external;
    function poolInfo(uint256) external view returns (uint128 accSynapsePerShare, uint64 lastRewardTime, uint64 allocPoint);
    function poolLength() external view returns (uint256 pools);
    function rewarder(uint256) external view returns (address);
    function set(uint256 _pid,uint256 _allocPoint,address _rewarder,bool overwrite) external;
    function setSynapsePerSecond(uint256 _synapsePerSecond) external;
    function synapsePerSecond() external view returns (uint256);
    function totalAllocPoint() external view returns (uint256);
    function transferOwnership(address newOwner,bool direct,bool renounce) external;
    function userInfo(uint256, address) external view returns (uint256 amount, int256 rewardDebt);
    function withdraw(uint256 pid,uint256 amount,address to) external;
    function withdrawAndHarvest(uint256 pid,uint256 amount,address to) external;
}