// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../infra/BeefyOracle/BeefyOracleHelper.sol";
import "@openzeppelin-4/contracts/interfaces/IERC4626.sol";

contract ERC4626Oracle {

    IERC4626 public vault;
    address public beefyOracle;

    constructor(IERC4626 _vault, address _beefyOracle) {
        vault = _vault;
        beefyOracle = _beefyOracle;
    }

    function getPrice(bytes memory) public returns (uint256 price, bool success) {
        address asset = vault.asset();
        uint amountOut = vault.convertToShares(10 ** vault.decimals());
        price = BeefyOracleHelper.priceFromBaseToken(beefyOracle, address(vault), asset, amountOut);
        return (price, true);
    }

    function validateData(bytes calldata data) external view {}
}