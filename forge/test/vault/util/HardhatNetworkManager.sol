// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import { stdJson } from "forge-std/StdJson.sol";
import { CommonBase } from "forge-std/Base.sol";

/**
 * Allow access and manipulation for hardhard networks
 * 
 * Inherits:
 * - CommonBase to get access to the `vm` lib
 */
contract HardhatNetworkManager is CommonBase {
    using stdJson for string;

    struct NetworkConfig {
        uint256 chainId;
        string name;
        string url;
    }

    // once network configs have been loaded from hardhat, they are stored here
    bool private _networkConfigCacheLoaded;
    mapping(string => NetworkConfig) private _networkConfigCache;
    // mapping from chain name to fork id
    // mostly used so users can reference chain names instead of fork ids
    mapping(string => uint) private _forks;

    // debug events
    event HardhatNetworkManager_Info_ConfigRead(string config);
    event HardhatNetworkManager_Debug_FoundChainConfig(NetworkConfig config);
    
    // This function modifier is used to load the network config from the hardhat config file.
    // The config file is read using a custom hardhat task, which outputs the network config
    // in json format. The json is then parsed into an array of NetworkConfig structs.
    // The modifier is used to prevent the network config from being read more than once per
    // execution.
    modifier _loadNetworkConfig() {
        // quick exit if we already loaded the config
        if(!_networkConfigCacheLoaded) {

            // use our custom hardhat task to print out the network config in json format
            string[] memory inputs = new string[](3);
            inputs[0] = "yarn";
            inputs[1] = "--silent";
            inputs[2] = "test-data:network-config";
            string memory jsonConfig = string(vm.ffi(inputs));
            require(bytes(jsonConfig).length > 0, "Could not read hardhat config");
            emit HardhatNetworkManager_Info_ConfigRead(jsonConfig);

            // parse the json into an array of network config
            bytes memory data = jsonConfig.parseRaw("*");

            NetworkConfig[] memory configs = abi.decode(data, (NetworkConfig[]));
            require(configs.length > 0, "Could not parse network config from json");

            for (uint i = 0 ; i < configs.length ; ++i) {
                emit HardhatNetworkManager_Debug_FoundChainConfig(configs[i]);
                // move the array to storage, no simple way to do that atm
                _networkConfigCache[configs[i].name] = configs[i];
            }

            _networkConfigCacheLoaded = true;
        }

        _;
    }

    function createHardhatNetworkFork(string memory networkName) public _loadNetworkConfig() {
        // find the rpc url
        NetworkConfig memory config = _networkConfigCache[networkName];
        vm.createSelectFork(config.url);
    }

    function createHardhatNetworkFork(string memory networkName, uint256 blockNumber) public _loadNetworkConfig() {
        // find the rpc url
        NetworkConfig memory config = _networkConfigCache[networkName];
        if (blockNumber > 0) vm.createSelectFork(config.url, blockNumber);
        else vm.createSelectFork(config.url);
    }
}