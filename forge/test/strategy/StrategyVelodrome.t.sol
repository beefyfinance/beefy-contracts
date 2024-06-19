// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "../../../contracts/BIFI/strategies/Velodrome/StrategyVelodromeGaugeV2.sol";
import "./BaseStrategyTest.t.sol";

contract StrategyVelodromeGaugeV2Test is BaseStrategyTest {

    StrategyVelodromeGaugeV2 strategy;

    function createStrategy(address _impl) internal override returns (address) {
        wantAmount = 50 ether;
        if (_impl == a0) strategy = new StrategyVelodromeGaugeV2();
        else strategy = StrategyVelodromeGaugeV2(_impl);
        return address(strategy);
    }

    function solidRouteToStr(ISolidlyRouter.Route[] memory a) public view returns (string memory t) {
        if (a.length == 0) return "[[]]";
        if (a.length == 1) return string.concat('[["', addrToStr(a[0].from), '", "', addrToStr(a[0].to), '", ', boolToStr(a[0].stable), ', "', addrToStr(a0), '"', ']]');
        t = string.concat('[["', addrToStr(a[0].from), '", "', addrToStr(a[0].to), '", ', boolToStr(a[0].stable), ', "', addrToStr(a0), '"', ']');
        for (uint i = 1; i < a.length; i++) {
            t = string.concat(t, ", ", string.concat('["', addrToStr(a[i].from), '", "', addrToStr(a[i].to), '", ', boolToStr(a[i].stable), ', "', addrToStr(a0), '"', ']'));
        }
        t = string.concat(t, "]");
    }
}