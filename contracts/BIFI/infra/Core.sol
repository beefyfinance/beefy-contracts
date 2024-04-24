// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { IBeefySwapper } from "../interfaces/beefy/IBeefySwapper.sol";
import { IBeefyOracle } from "../interfaces/beefy/IBeefyOracle.sol";
import { IFeeConfig } from "../interfaces/common/IFeeConfig.sol";

/// @title Core addresses
/// @author kexley, Beefy
/// @notice Core addresses to be referenced by strategies
contract Core is OwnableUpgradeable {

    /// @notice Emitted when the global pause state is changed
    event GlobalPause(bool paused);

    /// @notice Emitted when the swapper address is changed
    event SetSwapper(address swapper);

    /// @notice Emitted when the keeper address is changed
    event SetKeeper(address keeper);

    /// @notice Emitted when the beefy fee recipient address is changed
    event SetBeefyFeeRecipient(address beefyFeeRecipient);

    /// @notice Emitted when the beefy fee config address is changed
    event SetBeefyFeeConfig(address beefyFeeConfig);

    /// @notice The address of the native token
    address public native;

    /// @notice Swapper of tokens
    IBeefySwapper public swapper;

    /// @notice The address of the keeper
    address public keeper;

    /// @notice Beefy fee recipient
    address public beefyFeeRecipient;

    /// @notice Beefy fee configurator
    IFeeConfig public beefyFeeConfig;

    /// @notice Global pause state for all strategies
    bool public globalPause;

    /// @notice Caller is not manager
    error NotManager();

    /// @notice Throws if called by any account other than the owner or the keeper
    modifier onlyManager() {
        if (msg.sender != owner() && msg.sender != keeper) revert NotManager();
        _;
    }

    function initialize(
        address _native,
        address _keeper,
        address _swapper,
        address _beefyFeeRecipient,
        address _beefyFeeConfig
    ) external initializer {
        __Ownable_init();
        native = _native;
        keeper = _keeper;
        swapper = IBeefySwapper(_swapper);
        beefyFeeRecipient = _beefyFeeRecipient;
        beefyFeeConfig = IFeeConfig(_beefyFeeConfig);
    }

    /// @notice Pauses all strategies
    function pause() external onlyManager {
        globalPause = true;
        emit GlobalPause(true);
    }

    /// @notice Unpauses all strategies
    function unpause() external onlyOwner {
        globalPause = false;
        emit GlobalPause(false);
    }

    /// @notice Price oracle for tokens
    function oracle() external view returns (IBeefyOracle) {
        return swapper.oracle();
    }
    
    /// @notice Set the swapper address
    /// @param _swapper The new swapper address
    function setSwapper(address _swapper) external onlyOwner {
        swapper = IBeefySwapper(_swapper);
        emit SetSwapper(_swapper);
    }

    /// @notice Set the keeper address
    /// @param _keeper The new keeper address
    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
        emit SetKeeper(_keeper);
    }

    /// @notice Set the beefy fee recipient address
    /// @param _beefyFeeRecipient The new beefy fee recipient address
    function setBeefyFeeRecipient(address _beefyFeeRecipient) external onlyOwner {
        beefyFeeRecipient = _beefyFeeRecipient;
        emit SetBeefyFeeRecipient(_beefyFeeRecipient);
    }

    /// @notice Set the beefy fee config address
    /// @param _beefyFeeConfig The new beefy fee config address
    function setBeefyFeeConfig(address _beefyFeeConfig) external onlyOwner {
        beefyFeeConfig = IFeeConfig(_beefyFeeConfig);
        emit SetBeefyFeeConfig(_beefyFeeConfig);
    }
}
