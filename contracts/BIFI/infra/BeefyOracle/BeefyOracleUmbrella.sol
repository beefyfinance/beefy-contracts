// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { BeefyOracleHelper, BeefyOracleErrors } from "./BeefyOracleHelper.sol";

interface IUmbrella {
    function getPriceDataByName(string calldata _name) external view returns (uint8, uint24, uint32, uint128);
}

interface IRegistry {
    function getAddressByString(string memory _name) external view returns (address);
}

/// @title Beefy Oracle using Umbrella
/// @author Beefy, @weso
/// @notice On-chain oracle using Umbrella
library BeefyOracleUmbrella {


    /// @notice Fetch price from the Umbrella feed and scale to 18 decimals
    /// @return price Retrieved price from the Umbrella feed
    /// @return success Successful price fetch or not
    function getPrice(bytes calldata _data) external view returns (uint256 price, bool success) {
        string memory feed = abi.decode(_data, (string));
        IRegistry registry = IRegistry(0x4A28406ECE8fFd7A91789738a5ac15DAc44bFa1b);
        address umbrella = registry.getAddressByString("UmbrellaFeeds");
        uint8 decimals = 8;
        try IUmbrella(umbrella).getPriceDataByName(feed) returns (uint8, uint24, uint32, uint128 latestAnswer) {
                price = BeefyOracleHelper.scaleAmount(uint256(latestAnswer), decimals);
                success = true;
        } catch {}
    }

    /// @notice Data validation for new oracle data being added to central oracle
    function validateData(bytes calldata _data) external view {
        string memory feed = abi.decode(_data, (string));
        IRegistry registry = IRegistry(0x4A28406ECE8fFd7A91789738a5ac15DAc44bFa1b);
        address umbrella = registry.getAddressByString("UmbrellaFeeds");
        try IUmbrella(umbrella).getPriceDataByName(feed) returns (uint8, uint24, uint32, uint128) { 
        } catch { revert BeefyOracleErrors.NoAnswer(); }
    }
}