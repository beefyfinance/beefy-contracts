// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/common/IUniswapRouterETH.sol";
import "../Common/StratManager.sol";

contract StrategyCake is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // Tokens used
    address public lpPair;
    address public lpToken0;
    address public lpToken1;
    address public newLpPair;

    // Third Party Contracts
    address constant public oldUnirouter  = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);
    address constant public newUnirouter  = address(0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F);

    // Beefy Contracts
    address public immutable vault;
    address public immutable newVault;

    /**
     * @param _vault Address of parent vault
     */
    constructor(address _lpPair, address _newLpPair, address _newVault, address _vault) public {
        lpPair = _lpPair;
        lpToken0 = IUniswapV2Pair(lpPair).token0();
        lpToken1 = IUniswapV2Pair(lpPair).token1();
        newLpPair = _newLpPair;
        newVault = _newVault;
        vault = _vault;

        IERC20(cake).safeApprove(unirouter, uint(-1));
    }

    // required to accept funds from old strat
    function deposit() external {}

    function seed() external onlyOwner {
        // 1. Remove liquidity from old pair.

        // 2. Add liquidity to new pair.

        // 3. Send all funds to new vault.

        // 4. Call seed.
    }
}
