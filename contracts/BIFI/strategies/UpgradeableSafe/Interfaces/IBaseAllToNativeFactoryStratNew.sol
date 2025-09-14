// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBaseAllToNativeFactoryStratNew {

    struct Addresses {
        address want;
        address depositToken;
        address factory;
        address vault;
        address swapper;
        address strategist;
    }
    
    struct BaseAllToNativeFactoryStratStorage {
        Addresses addresses;
        address native;
        address[] rewards;
        uint256 lastHarvest;
        uint256 totalLocked;
        uint256 lockDuration;
        bool harvestOnDeposit;
        mapping(address => uint) minAmounts; // tokens minimum amount to be swapped
    }

    event StratHarvest(address indexed harvester, uint256 wantHarvested, uint256 tvl);
    event Deposit(uint256 tvl);
    event Withdraw(uint256 tvl);
    event ChargedFees(uint256 callFees, uint256 beefyFees, uint256 strategistFees);
    event SetVault(address vault);
    event SetSwapper(address swapper);
    event SetStrategist(address strategist);

    error StrategyPaused();
    error NotManager();
    error NotVault();
    error NotWant();
    error NotNative();
    error NotStrategist();
}