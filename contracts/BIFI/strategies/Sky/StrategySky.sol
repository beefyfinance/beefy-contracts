// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../Common/BaseAllToNativeFactoryStrat.sol";

interface ILockstake {
    function vat() external view returns (address);
    function ilk() external view returns (bytes32);
    function open(uint256 index) external returns (address urn);
    function selectFarm(address owner, uint256 index, address farm, uint16 ref) external;
    function ownerUrns(address owner, uint index) external view returns (address);
    function urnFarms(address urn) external view returns (address farm);
    function lock(address owner, uint256 index, uint256 wad, uint16 ref) external;
    function free(address owner, uint256 index, address to, uint256 wad) external returns (uint256 freed);
    function getReward(address owner, uint256 index, address farm, address to) external returns (uint256 amt);
}

interface IVat {
    function urns(bytes32 ilk, address urn) external view returns (uint256, uint256);
}

contract StrategySky is BaseAllToNativeFactoryStrat {
    using SafeERC20 for IERC20;

    ILockstake public lockstake;
    IVat public vat;
    bytes32 public ilk;

    function initialize(
        address _lockstake,
        address _farm,
        bool _harvestOnDeposit,
        address[] calldata _rewards,
        Addresses calldata _addresses
    ) public initializer {
        lockstake = ILockstake(_lockstake);
        vat = IVat(lockstake.vat());
        ilk = lockstake.ilk();

        lockstake.open(0);
        lockstake.selectFarm(address(this), 0, _farm, 0);

        __BaseStrategy_init(_addresses, _rewards);
        if (_harvestOnDeposit) setHarvestOnDeposit(true);
    }

    function stratName() public pure override returns (string memory) {
        return "SkyLockstake";
    }

    function balanceOfPool() public view override returns (uint) {
        address urn = lockstake.ownerUrns(address(this), 0);
        (uint ink,) = vat.urns(ilk, urn);
        return ink;
    }

    function _deposit(uint amount) internal override {
        IERC20(want).forceApprove(address(lockstake), amount);
        lockstake.lock(address(this), 0, amount, 0);
    }

    function _withdraw(uint amount) internal override {
        if (amount > 0) {
            lockstake.free(address(this), 0, address(this), amount);
        }
    }

    function _emergencyWithdraw() internal override {
        _withdraw(balanceOfPool());
    }

    function _claim() internal override {
        address urn = lockstake.ownerUrns(address(this), 0);
        address farm = lockstake.urnFarms(urn);
        lockstake.getReward(address(this), 0, farm, address(this));
    }

    function _verifyRewardToken(address token) internal view override {}
}