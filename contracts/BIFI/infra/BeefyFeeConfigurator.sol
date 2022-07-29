// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

interface IStrategy {
    function vault() external view returns (address);
}

contract BeefyFeeConfigurator is OwnableUpgradeable {

    struct FeeCategory {
        uint256 total;
        uint256 beefy;
        uint256 call;
        uint256 strategist;
        string label;
        bool active;
    }

    address public keeper;
    uint256 public totalLimit;
    uint256 constant DIVISOR = 1 ether;

    mapping(address => uint256) public vaultFeeId;
    mapping(uint256 => FeeCategory) internal feeCategory;

    event UpdateVault(address indexed vault, uint256 indexed id);
    event SetFeeCategory(
        uint256 indexed id,
        uint256 total,
        uint256 beefy,
        uint256 call,
        uint256 strategist,
        string label,
        bool active
    );
    event SetTotalLimit(uint256 totalLimit);
    event Pause(uint256 indexed id);
    event Unpause(uint256 indexed id);

    function initialize(
        address _keeper,
        uint256 _totalLimit
    ) public initializer {
        __Ownable_init();

        keeper = _keeper;
        totalLimit = _totalLimit;
    }

    // checks that caller is either owner or keeper
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // fetch fees for the connected vault when called by a strategy
    function getFees() external view returns (FeeCategory memory) {
        address vault = IStrategy(msg.sender).vault();
        return getFeeCategory(vaultFeeId[vault], false);
    }

    // fetch fees for a vault
    function getFees(address _vault) external view returns (FeeCategory memory) {
        return getFeeCategory(vaultFeeId[_vault], false);
    }

    // fetch fees for a vault, _adjust option to view fees as % of total harvest instead of % of total fee
    function getFees(address _vault, bool _adjust) external view returns (FeeCategory memory) {
        return getFeeCategory(vaultFeeId[_vault], _adjust);
    }

    // fetch fee category for an id if active, otherwise return default category
    // _adjust == true: view fees as % of total harvest instead of % of total fee
    function getFeeCategory(uint256 _id, bool _adjust) public view returns (FeeCategory memory fees) {
        uint256 id = feeCategory[_id].active ? _id : 0;
        fees = feeCategory[id];
        if (_adjust) {
            uint256 _totalFee = fees.total;
            fees.beefy = fees.beefy * _totalFee / DIVISOR;
            fees.call = fees.call * _totalFee / DIVISOR;
            fees.strategist = fees.strategist * _totalFee / DIVISOR;
        }
    }

    // set a fee category id for a vault
    function updateVault(address _vault, uint256 _feeId) external onlyManager {
        vaultFeeId[_vault] = _feeId;
        emit UpdateVault(_vault, _feeId);
    }

    // set fee category ids for multiple vaults at once
    function batchUpdateVaults(address[] memory _vaults, uint256[] memory _feeIds) external onlyManager {
        uint256 vaultLength = _vaults.length;
        for (uint256 i = 0; i < vaultLength; i++) {
            vaultFeeId[_vaults[i]] = _feeIds[i];
            emit UpdateVault(_vaults[i], _feeIds[i]);
        }
    }

    // set values for a fee category using the relative split for call and strategist
    // i.e. call = 0.01 ether == 1% of total fee
    // _adjust == true: input call and strat fee as % of total harvest
    function setFeeCategory(
        uint256 _id,
        uint256 _total,
        uint256 _call,
        uint256 _strategist,
        string memory _label,
        bool _active,
        bool _adjust
    ) external onlyOwner {
        require(_total <= totalLimit, ">totalLimit");
        if (_adjust) {
            _call = _call * DIVISOR / _total;
            _strategist = _strategist * DIVISOR / _total;
        }
        uint256 beefy = DIVISOR - _call - _strategist;

        FeeCategory memory category = FeeCategory(_total, beefy, _call, _strategist, _label, _active);
        feeCategory[_id] = category;
        emit SetFeeCategory(_id, _total, beefy, _call, _strategist, _label, _active);
    }

    // deactivate a fee category making all vaults with this fee id revert to default fees
    function pause(uint256 _id) external onlyManager {
        feeCategory[_id].active = false;
        emit Pause(_id);
    }

    // reactivate a fee category
    function unpause(uint256 _id) external onlyManager {
        feeCategory[_id].active = true;
        emit Unpause(_id);
    }

    // change keeper
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
    }
}