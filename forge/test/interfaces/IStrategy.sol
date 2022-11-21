// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.9.0;

interface IStrategy {
    event Deposit(uint256 tvl);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event Paused(address account);
    event StratHarvest(
        address indexed harvester,
        uint256 wantHarvested,
        uint256 tvl
    );
    event Unpaused(address account);
    event Withdraw(uint256 tvl);

    // All strats

    function MAX_CALL_FEE() external view returns (uint256);

    function MAX_FEE() external view returns (uint256);

    function STRATEGIST_FEE() external view returns (uint256);

    function WITHDRAWAL_FEE_CAP() external view returns (uint256);

    function WITHDRAWAL_MAX() external view returns (uint256);

    function balanceOf() external view returns (uint256);

    function balanceOfPool() external view returns (uint256);

    function balanceOfWant() external view returns (uint256);

    function beefyFee() external view returns (uint256);

    function beefyFeeRecipient() external view returns (address);

    function beefyFeeConfig() external view returns (address);

    function beforeDeposit() external;

    function callFee() external view returns (uint256);

    function callReward() external view returns (uint256);

    function deposit() external;

    function harvest(address callFeeRecipient) external;

    function harvest() external;

    function harvestOnDeposit() external view returns (bool);

    function keeper() external view returns (address);

    function lastHarvest() external view returns (uint256);

    function lpToken0() external view returns (address);

    function lpToken1() external view returns (address);

    function managerHarvest() external;

    function native() external view returns (address);

    function output() external view returns (address);

    function outputToLp0() external view returns (address[] memory);

    function outputToLp0Route(uint256) external view returns (address);

    function outputToLp1() external view returns (address[] memory);

    function outputToLp1Route(uint256) external view returns (address);

    function outputToNative() external view returns (address[] memory);

    function outputToNativeRoute(uint256) external view returns (address);

    function owner() external view returns (address);

    function panic() external;

    function pause() external;

    function paused() external view returns (bool);

    function renounceOwnership() external;

    function retireStrat() external;

    function rewardsAvailable() external view returns (uint256);

    function setBeefyFeeRecipient(address _beefyFeeRecipient) external;

    function setCallFee(uint256 _fee) external;

    function setHarvestOnDeposit(bool _harvestOnDeposit) external;

    function setKeeper(address _keeper) external;

    function setStrategist(address _strategist) external;

    function setUnirouter(address _unirouter) external;

    function setVault(address _vault) external;

    function setWithdrawalFee(uint256 _fee) external;

    function strategist() external view returns (address);

    function transferOwnership(address newOwner) external;

    function unirouter() external view returns (address);

    function unpause() external;

    function vault() external view returns (address);

    function want() external view returns (address);

    function withdraw(uint256 _amount) external;

    function withdrawalFee() external view returns (uint256);

    // Only chef based strats
    function chef() external view returns (address); 

    function setPendingRewardsFunctionName(
        string memory _pendingRewardsFunctionName
    ) external;

    function pendingRewardsFunctionName() external view returns (string memory);

    function poolId() external view returns (uint256);

    // Only gas throttled strats
    function gasprice() external view returns (address); 

    function shouldGasThrottle() external view returns (bool);

    function setShouldGasThrottle(bool _shouldGasThrottle) external;

}