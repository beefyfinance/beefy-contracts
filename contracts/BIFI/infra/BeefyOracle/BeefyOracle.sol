// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import { ISubOracle } from "../../interfaces/oracle/ISubOracle.sol";

/// @title Beefy Oracle
/// @author Beefy, @kexley
/// @notice On-chain oracle using various sources
contract BeefyOracle is OwnableUpgradeable {

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
    mapping(address => LatestPrice) public latestPrice;

    /// @notice Oracle library address and payload for delegating the price calculation of a token
    mapping(address => SubOracle) public subOracle;

    /// @notice Length of time in seconds before a price goes stale
    uint256 public staleness;

    /// @notice Price of a token has been updated
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);

    /// @notice New oracle has been set
    event SetOracle(address indexed token, address oracle, bytes data);

    /// @notice New staleness has been set
    event SetStaleness(uint256 staleness);

    /// @notice Initialize the contract
    /// @dev Ownership is transferred to msg.sender
    function initialize() external initializer {
        __Ownable_init();
    }

    /// @notice Fetch the most recent stored price for a token
    /// @param _token Address of the token being fetched
    /// @return price Price of the token
    function getPrice(address _token) external view returns (uint256 price) {
        price = latestPrice[_token].price;
    }

    /// @notice Fetch the most recent stored price for an array of tokens
    /// @param _tokens Addresses of the tokens being fetched
    /// @return prices Prices of the tokens
    function getPrice(address[] calldata _tokens) external view returns (uint256[] memory prices) {
        for (uint i; i < _tokens.length; i++) {
            prices[i] = latestPrice[_tokens[i]].price;
        }
    }

    /// @notice Fetch an updated price for a token
    /// @param _token Address of the token being fetched
    /// @return price Updated price of the token
    /// @return success Price update was success or not
    function getFreshPrice(address _token) external returns (uint256 price, bool success) {
        (price, success) = _getFreshPrice(_token);
    }

    /// @notice Fetch updated prices for an array of tokens
    /// @param _tokens Addresses of the tokens being fetched
    /// @return prices Updated prices of the tokens
    /// @return successes Price updates were a success or not
    function getFreshPrice(
        address[] calldata _tokens
    ) external returns (uint256[] memory prices, bool[] memory successes) {
        for (uint i; i < _tokens.length; i++) {
            (prices[i], successes[i]) = _getFreshPrice(_tokens[i]);
        }
    }

    /// @dev If the price is stale then calculate a new price by delegating to the sub oracle
    /// @param _token Address of the token being fetched
    /// @return price Updated price of the token
    /// @return success Price update was success or not
    function _getFreshPrice(address _token) private returns (uint256 price, bool success) {
        if (latestPrice[_token].timestamp + staleness > block.timestamp) {
            price = latestPrice[_token].price;
            success = true;
        } else {
            (price, success) = ISubOracle(subOracle[_token].oracle).getPrice(subOracle[_token].data);
            if (success) {
                latestPrice[_token] = LatestPrice({price: price, timestamp: block.timestamp});
                emit PriceUpdated(_token, price, block.timestamp);
            }
        }
    }

    /// @notice Owner function to set a sub oracle and data for a token
    /// @dev The payload will be validated against the library
    /// @param _token Address of the token being fetched
    /// @param _oracle Address of the library used to calculate the price
    /// @param _data Payload specific to the token that will be used by the library
    function setOracle(address _token, address _oracle, bytes calldata _data) external onlyOwner {
        _setOracle(_token, _oracle, _data);
    }

    /// @notice Owner function to set a sub oracle and data for an array of tokens
    /// @dev The payloads will be validated against the libraries
    /// @param _tokens Addresses of the tokens being fetched
    /// @param _oracles Addresses of the libraries used to calculate the price
    /// @param _datas Payloads specific to the tokens that will be used by the libraries
    function setOracle(
        address[] calldata _tokens,
        address[] calldata _oracles,
        bytes[] calldata _datas
    ) external onlyOwner {
        for (uint i; i < _tokens.length;) {
            _setOracle(_tokens[i], _oracles[i], _datas[i]);
            unchecked { i++; }
        }
    }

    /// @dev Set the sub oracle and data for a token, it also validates that the data is correct
    /// @param _token Address of the token being fetched
    /// @param _oracle Address of the library used to calculate the price
    /// @param _data Payload specific to the token that will be used by the library
    function _setOracle(address _token, address _oracle, bytes calldata _data) private {
        ISubOracle(_oracle).validateData(_data);
        subOracle[_token] = SubOracle({oracle: _oracle, data: _data});
        emit SetOracle(_token, _oracle, _data);
    }

    /// @notice Owner function to set the staleness
    /// @param _staleness Length of time in seconds before a price becomes stale
    function setStaleness(uint256 _staleness) external onlyOwner {
        staleness = _staleness;
        emit SetStaleness(_staleness);
    }
}
