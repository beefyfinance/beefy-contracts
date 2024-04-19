// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { ISubOracle } from "../../interfaces/oracle/ISubOracle.sol";

/// @title Beefy Oracle
/// @author Beefy, @kexley
/// @notice On-chain oracle using various sources
contract BeefyOracle is OwnableUpgradeable {

    /// @dev Caller is not owner or manager
    error NotManager();

    /// @dev Struct for the latest price of a token with the timestamp
    /// @param price Stored price
    /// @param timestamp Last update timestamp
    struct LatestPrice {
        uint256 price;
        uint256 timestamp;
    }

    /// @dev Struct for delegating the price calculation to a library using stored data
    /// @param oracle Address of the library for a particular oracle type
    /// @param data Stored data for calculating the price of a specific token using the library
    struct SubOracle {
        address oracle;
        bytes data;
    }

    /// @notice Latest price of a token with a timestamp
    mapping(address => mapping(address => LatestPrice)) public latestPrice;

    /// @notice Oracle library address and payload for delegating the price calculation of a token
    mapping(address => mapping(address => SubOracle)) public subOracle;

    /// @notice Length of time in seconds before a price goes stale
    uint256 public staleness;

    /// @notice Manager of this contract
    address public keeper;

    /// @notice Price of a token has been updated
    /// @param caller Address of the caller
    /// @param token Token address
    /// @param price New price
    /// @param timestamp Timestamp of price fetch
    event PriceUpdated(address indexed caller, address indexed token, uint256 price, uint256 timestamp);

    /// @notice New oracle has been set
    /// @param caller Address of the caller
    /// @param token Token address
    /// @param oracle Library address for price fetch
    /// @param data Data to pass to library to calculate the price for that token
    event SetOracle(address indexed caller, address indexed token, address oracle, bytes data);

    /// @notice New staleness has been set
    /// @param staleness Length of time a price stays fresh for
    event SetStaleness(uint256 staleness);

    /// @notice Set a new manager
    /// @param keeper New manager address
    event SetKeeper(address keeper);

    modifier onlyManager {
        if (msg.sender != owner() && msg.sender != keeper) revert NotManager();
        _;
    }

    /// @notice Initialize the contract
    /// @dev Ownership is transferred to msg.sender
    /// @param _keeper Manager of this contract
    function initialize(address _keeper) external initializer {
        __Ownable_init();
        keeper = _keeper;
    }

    /// @notice Fetch the most recent stored price for a token
    /// @param _token Address of the token being fetched
    /// @return price Price of the token
    function getPrice(address _token) external view returns (uint256 price) {
        price = latestPrice[address(0)][_token].price;
    }

    /// @notice Fetch the most recent stored price for a token using a specific route, tries the
    /// default price first
    /// @param _caller Address of the caller
    /// @param _token Address of the token being fetched
    /// @return price Price of the token
    function getPrice(address _caller, address _token) external view returns (uint256 price) {
        price = latestPrice[address(0)][_token].price;
        if (price == 0) price = latestPrice[_caller][_token].price;
    }

    /// @notice Fetch an updated price for a token
    /// @param _token Address of the token being fetched
    /// @return price Updated price of the token
    /// @return success Price update was success or not
    function getFreshPrice(address _token) external returns (uint256 price, bool success) {
        (price, success) = _getFreshPrice(address(0), _token);
    }

    /// @notice Fetch an updated price for a token using a specific route, tries the default route 
    /// first
    /// @param _caller Address of the caller
    /// @param _token Address of the token being fetched
    /// @return price Updated price of the token
    /// @return success Price update was success or not
    function getFreshPrice(address _caller, address _token) external returns (uint256 price, bool success) {
        if (subOracle(_caller, _token).oracle != address(0)) _caller = address(0);
        (price, success) = _getFreshPrice(_caller, _token);
    }

    /// @dev If the price is stale then calculate a new price by delegating to the sub oracle
    /// @param _caller Address of the caller
    /// @param _token Address of the token being fetched
    /// @return price Updated price of the token
    /// @return success Price update was success or not
    function _getFreshPrice(address _caller, address _token) private returns (uint256 price, bool success) {
        if (latestPrice[_caller][_token].timestamp + staleness > block.timestamp) {
            price = latestPrice[_caller][_token].price;
            success = true;
        } else {
            (price, success) = 
                ISubOracle(subOracle[_caller][_token].oracle).getPrice(subOracle[_caller][_token].data);
            if (success) {
                latestPrice[_caller][_token] = LatestPrice({price: price, timestamp: block.timestamp});
                emit PriceUpdated(_caller, _token, price, block.timestamp);
            }
        }
    }

    /* ----------------------------------- OWNER FUNCTIONS ----------------------------------- */

    /// @notice Owner function to set a sub oracle and data for an array of tokens
    /// @dev The payloads will be validated against the libraries
    /// @param _tokens Addresses of the tokens being fetched
    /// @param _oracles Addresses of the libraries used to calculate the price
    /// @param _datas Payloads specific to the tokens that will be used by the libraries
    function setOracles(
        address[] calldata _tokens,
        address[] calldata _oracles,
        bytes[] calldata _datas
    ) external {
        bool isManager = _isCallerManager();
        for (uint i; i < _tokens.length; ++i) {
            _setOracle(_tokens[i], _oracles[i], _datas[i], isManager);
        }
    }

    /// @dev Set the sub oracle and data for a token, it also validates that the data is correct
    /// @param _token Address of the token being fetched
    /// @param _oracle Address of the library used to calculate the price
    /// @param _data Payload specific to the token that will be used by the library
    /// @param _isManager Caller is a manager or not
    function _setOracle(address _token, address _oracle, bytes calldata _data, bool _isManager) private {
        ISubOracle(_oracle).validateData(_data);
        address caller = _isManager ? address(0) : msg.sender;
        subOracle[caller][_token] = SubOracle({oracle: _oracle, data: _data});
        _getFreshPrice(caller, _token);
        emit SetOracle(caller, _token, _oracle, _data);
    }

    /// @notice Manager function to set the keeper
    /// @param _keeper New manager address
    function setKeeper(address _keeper) external onlyManager {
        keeper = _keeper;
        emit SetKeeper(_keeper);
    }

    /// @notice Owner function to set the staleness
    /// @param _staleness Length of time in seconds before a price becomes stale
    function setStaleness(uint256 _staleness) external onlyOwner {
        staleness = _staleness;
        emit SetStaleness(_staleness);
    }

    /// @dev Internal function to check if caller is manager
    function _isCallerManager() internal view returns (bool isManager) {
        if (msg.sender == owner() || msg.sender == keeper) isManager = true;
    }
}
