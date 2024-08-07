// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./BaseAllToNativeTest.t.sol";
import {StrategyDotDotEllipsisSwapper, StratFeeManager} from "../../../contracts/BIFI/strategies/Ellipsis/StrategyDotDotEllipsisSwapper.sol";
import "../../../contracts/BIFI/infra/SimpleSwapper.sol";

contract StrategyDotDotEllipsisSwapperTest is BaseAllToNativeTest {

    StrategyDotDotEllipsisSwapper strategy;
    address native = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address keeper = 0x4fED5491693007f0CD49f4614FFC38Ab6A04B619;
    address swapper = 0xC3cc18aC37168D3b708C0e72Fe9678084e4Cd7b2;
    address _want = 0x5c73804FeDd39f3388E03F4aa1fE06a1C0e60c8e;

    function createStrategy(address _impl) internal override returns (address) {
        if (_impl == a0) {
            setupSwapper();
            strategy = new StrategyDotDotEllipsisSwapper(
                _want,
                native,
                StratFeeManager.CommonAddresses(
                    address(0),
                    swapper,
                    keeper, keeper,
                    0x02Ae4716B9D5d48Db1445814b0eDE39f5c28264B,
                    0x97F86f2dC863D98e423E288938dF257D1b6e1553
                )
            );
            deal(strategy.epx(), address(strategy), 500000*1e18);
        }
        else strategy = StrategyDotDotEllipsisSwapper(payable(_impl));
        return address(strategy);
    }

    function setupSwapper() public {
//        vm.prank(keeper);
//        (bool success,) = swapper.call(hex'84aad7fd000000000000000000000000af41054c1487b0e5e2b9250c0332ecbce6ce9d71000000000000000000000000bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c00000000000000000000000000000000000000000000000000000000000000600000000000000000000000004362fe9ac48e7c5ea85a359418bbd7471979f5c2000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000440000000000000000000000000000000000000000000000000000000000000064df791e50000000000000000000000000af41054c1487b0e5e2b9250c0332ecbce6ce9d71000000000000000000000000bb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c000000000000000000000000000000000000000000000000000abcdef0abcdef00000000000000000000000000000000000000000000000000000000');
    }
}