// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin-4/contracts/access/Ownable.sol";
import "@openzeppelin-4/contracts/security/Pausable.sol";
import "../../interfaces/common/IFeeConfig.sol";

contract StratFeeManager is Ownable, Pausable {

    struct CommonAddresses {
        address vault;
        address unirouter;
        address keeper;
        address strategist;
        address beefyFeeRecipient;
        address beefyFeeConfig;
    }

    // common addresses for the strategy
    address public vault;
    address public unirouter;
    address public keeper;
    address public strategist;
    address public beefyFeeRecipient;
    address public beefyFeeConfig;

    uint constant DIVISOR = 1 ether;
    uint constant public WITHDRAWAL_FEE_CAP = 50;
    uint constant public WITHDRAWAL_MAX = 10000;
    uint public withdrawalFee = 10;

    constructor(
        CommonAddresses memory _commonAddresses
    ) {
        vault = _commonAddresses.vault;
        unirouter = _commonAddresses.unirouter;
        keeper = _commonAddresses.keeper;
        strategist = _commonAddresses.strategist;
        beefyFeeRecipient = _commonAddresses.beefyFeeRecipient;
        beefyFeeConfig = _commonAddresses.beefyFeeConfig;
    }

    // checks that caller is either owner or keeper.
    modifier onlyManager() {
        require(msg.sender == owner() || msg.sender == keeper, "!manager");
        _;
    }

    // fetch fees from config contract
    function fees() public view returns (IFeeConfig.FeeCategory memory) {
        return IFeeConfig(beefyFeeConfig).getFees();
    }

    // adjust withdrawal fee
    function setWithdrawalFee(uint256 _fee) public onlyManager {
        require(_fee <= WITHDRAWAL_FEE_CAP, "!cap");
        withdrawalFee = _fee;
    }

    // set new vault (only for strategy upgrades)
    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    // set new unirouter
    function setUnirouter(address _unirouter) external onlyOwner {
        unirouter = _unirouter;
    }

    // set new keeper to manage strat
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
    }

    // set new strategist address to receive strat fees
    function setStrategist(address _strategist) external {
        require(msg.sender == strategist, "!strategist");
        strategist = _strategist;
    }

    // set new beefy fee address to receive beefy fees
    function setBeefyFeeRecipient(address _beefyFeeRecipient) external onlyOwner {
        beefyFeeRecipient = _beefyFeeRecipient;
    }

    // set new fee config address to fetch fees
    function setBeefyFeeConfig(address _beefyFeeConfig) external onlyOwner {
        beefyFeeConfig = _beefyFeeConfig;
    }

    function beforeDeposit() external virtual {}
}