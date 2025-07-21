// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface IBoooooost {
    function cloneContract(address implementation) external returns (address);
    function initialize(
        address _stakedToken,
        address _rewardToken,
        uint256 _duration,
        address _manager,
        address _treasury
    ) external;
    function setTreasuryFee(uint256 _fee) external;
    function transferOwnership(address owner) external;
}

contract BeefyBoostFactory {
    address public factory;
    address public boostImpl;
    address public deployer;

    event BoostDeployed(address indexed boost);

    constructor(address _factory, address _boostImpl) {
        factory = _factory;
        boostImpl = _boostImpl;
        deployer = msg.sender;
    }

    function booooost(address mooToken, address rewardToken, uint duration_in_sec) external {
        IBoooooost boost = IBoooooost(IBoooooost(factory).cloneContract(boostImpl));
        boost.initialize(mooToken, rewardToken, duration_in_sec, msg.sender, address(0));
        boost.setTreasuryFee(0);
        boost.transferOwnership(deployer);
        emit BoostDeployed(address(boost));
    }
}
