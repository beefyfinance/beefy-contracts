// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IBeefySwapper } from "./IBeefySwapper.sol";
import { IBeefyOracle } from "./IBeefyOracle.sol";
import { IFeeConfig } from "../common/IFeeConfig.sol";

interface IBeefyCore {

    function native() external view returns (address);
    function swapper() external view returns (IBeefySwapper);
    function oracle() external view returns (IBeefyOracle);
    function keeper() external view returns (address);
    function beefyFeeRecipient() external view returns (address);
    function beefyFeeConfig() external view returns (IFeeConfig);
    function globalPause() external view returns (bool);

    function pause() external;
    function unpause() external;
    function setSwapper(address _swapper) external;
    function setKeeper(address _keeper) external;
    function setBeefyFeeRecipient(address _beefyFeeRecipient) external;
    function setBeefyFeeConfig(address _beefyFeeConfig) external;
}
