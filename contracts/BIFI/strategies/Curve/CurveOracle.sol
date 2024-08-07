// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../infra/BeefyOracle/BeefyOracleHelper.sol";

interface ICurvePool {
    function price_oracle() external view returns (uint);
}

contract CurveOracle {
    ICurvePool public pool;
    address public token;
    address public baseToken;
    address public beefyOracle;

    constructor(ICurvePool _pool, address _token, address _baseToken, address _beefyOracle) {
        pool = _pool;
        token = _token;
        baseToken = _baseToken;
        beefyOracle = _beefyOracle;
    }

    function getPrice(bytes memory) public returns (uint256 price, bool success) {
        uint priceInBase = pool.price_oracle();
        price = BeefyOracleHelper.priceFromBaseToken(beefyOracle, token, baseToken, priceInBase);
        return (price, true);
    }

    function validateData(bytes calldata data) external view {}
}