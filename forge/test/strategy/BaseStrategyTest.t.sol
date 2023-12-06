// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//import "forge-std/Test.sol";
import "../../../node_modules/forge-std/src/Test.sol";

// Users
import "../users/VaultUser.sol";
// Interfaces
import "../interfaces/IERC20Like.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";

abstract contract BaseStrategyTest is Test {

    IVault private vault;
    IStrategy private strategy;
    IERC20Like private want;
    VaultUser private user;
    uint private wantAmount = 50000 ether;

    function initBase(IVault _vault, IStrategy _strat) internal {
        vault = _vault;
        strategy = _strat;
        want = IERC20Like(vault.want());
        user = new VaultUser();
        deal(vault.want(), address(user), wantAmount);
    }

    function test_depositAndWithdraw() external {
        _depositIntoVault(user, wantAmount);
        assertEq(want.balanceOf(address(user)), 0, "User balance != 0 after deposit");
        assertGe(vault.balance(), wantAmount, "Vault balance < wantAmount");

        uint vaultBal = vault.balance();
        uint balOfPool = strategy.balanceOfPool();
        uint balOfWant = strategy.balanceOfWant();
        assertGe(balOfPool, wantAmount, "balOfPool < wantAmount"); // if deposit fee could be GT want * 99 / 100
        assertEq(balOfPool, vaultBal, "balOfPool != vaultBal");
        assertEq(balOfWant, 0, "Strategy.balanceOfWant != 0");

        console.log("Panic");
        vm.prank(strategy.keeper());
        strategy.panic();
        uint vaultBalAfterPanic = vault.balance();
        uint balOfPoolAfterPanic = strategy.balanceOfPool();
        uint balOfWantAfterPanic = strategy.balanceOfWant();
        // Vault balances are correct after panic.
        assertEq(vaultBalAfterPanic, vaultBal, "vaultBalAfterPanic"); // vaultBal * 99 / 100
        assertLe(balOfPoolAfterPanic, 1, "balOfPoolAfterPanic");
        assertGt(balOfPool, balOfPoolAfterPanic, "balOfPool");
        assertGt(balOfWantAfterPanic, balOfWant, "balOfWantAfterPanic");

        console.log("Unpause");
        vm.prank(strategy.keeper());
        strategy.unpause();
        uint vaultBalAfterUnpause = vault.balance();
        uint balOfPoolAfterUnpause = strategy.balanceOfPool();
        uint balOfWantAfterUnpause = strategy.balanceOfWant();
        assertEq(vaultBalAfterUnpause, vaultBalAfterPanic, "vaultBalAfterUnpause");
        assertEq(balOfWantAfterUnpause, 0, "balOfWantAfterUnpause != 0");
        assertEq(balOfPoolAfterUnpause, vaultBalAfterUnpause, "balOfPoolAfterUnpause");

        console.log("Withdrawing all");
        user.withdrawAll(vault);

        uint wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, wantAmount, "Expected wantBalanceFinal <= wantAmount");
        assertGt(wantBalanceFinal, wantAmount * 99 / 100, "Expected wantBalanceFinal > wantAmount * 99 / 100");
    }

    function test_depositWithHod() external {
        _depositIntoVault(user, wantAmount);
        uint pps = vault.getPricePerFullShare();
        assertGe(pps, 1e18, "Initial pps < 1");
        assertGe(vault.balance(), wantAmount, "Vault balance < wantAmount");

        console.log("setHarvestOnDeposit true");
        vm.prank(strategy.keeper());
        strategy.setHarvestOnDeposit(true);
        skip(1 days);
        deal(vault.want(), address(user), wantAmount);

        // trigger harvestOnDeposit
        _depositIntoVault(user, wantAmount);
        // in case of lockedProfit harvested balance is not available right away
        skip(1 days);
        assertGt(vault.getPricePerFullShare(), pps, "Not harvested");
        uint vaultBal = vault.balance();

        console.log("Withdrawing all");
        user.withdrawAll(vault);

        uint wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, vaultBal, "wantBalanceFinal > vaultBal");
        assertEq(vault.balance(), vaultBal - wantBalanceFinal, "vaultBal != vaultBal - wantBalanceFinal");
    }

    function test_harvest() external {
        _depositIntoVault(user, wantAmount);
        uint vaultBalance = vault.balance();
        assertGe(vaultBalance, wantAmount, "Vault balance < wantAmount");

        uint pps = vault.getPricePerFullShare();
        uint lastHarvest = strategy.lastHarvest();

        skip(1 days);
        console.log("Harvesting vault");
        strategy.harvest();

        // in case of lockedProfit harvested balance is not available right away
        skip(1 days);

        uint256 vaultBalAfterHarvest = vault.balance();
        uint256 ppsAfterHarvest = vault.getPricePerFullShare();
        uint256 lastHarvestAfterHarvest = strategy.lastHarvest();
        assertGt(vaultBalAfterHarvest, vaultBalance, "Harvested 0");
        assertGt(ppsAfterHarvest, pps, "Expected ppsAfterHarvest > initial");
        assertGt(lastHarvestAfterHarvest, lastHarvest, "Expected lastHarvestAfterHarvest > lastHarvest");

        console.log("Withdraw all");
        user.withdrawAll(vault);
        uint wantBalAfterWithdrawal = want.balanceOf(address(user));
        console.log("User want balance", wantBalAfterWithdrawal);
        assertLe(wantBalAfterWithdrawal, vaultBalAfterHarvest, "wantBalAfterWithdrawal too big");
        assertGt(wantBalAfterWithdrawal, vaultBalAfterHarvest * 99 / 100, "wantBalAfterWithdrawal too small");

        console.log("Deposit all");
        user.depositAll(vault);
        uint wantBalFinal = want.balanceOf(address(user));
        uint vaultBalFinal = vault.balance();
        uint balOfPoolFinal = strategy.balanceOfPool();
        uint balOfWantFinal = strategy.balanceOfWant();
        assertEq(wantBalFinal, 0, "wantBalFinal != 0");
        assertGt(vaultBalFinal, vaultBalAfterHarvest * 99 / 100, "vaultBalFinal != vaultBalAfterHarvest");
        assertEq(balOfPoolFinal, vaultBalFinal, "balOfPoolFinal != vaultBalFinal");
        assertEq(balOfWantFinal, 0, "balOfWantFinal != 0");
    }

    /*         */
    /* Helpers */
    /*         */

    function _depositIntoVault(VaultUser user_, uint amount) internal {
        console.log("Approving want");
        user_.infiniteApprove(address(want), address(vault));
        console.log("Depositing want into vault", amount);
        user_.deposit(vault, amount);
    }

    // uniswap v2 route to v3 path, 3000 = 0.3%, 500 = 0.05%
    function routeToPath(address[] memory _route, uint24[] memory _fee) public pure returns (bytes memory path) {
        path = abi.encodePacked(_route[0]);
        uint256 feeLength = _fee.length;
        for (uint256 i = 0; i < feeLength; i++) {
            path = abi.encodePacked(path, _fee[i], _route[i+1]);
        }
    }

    function toPath(address t1, address t2, uint24 fee) public pure returns (bytes memory path) {
        return abi.encodePacked(t1, fee, t2);
    }

    function route(address t1, address t2) internal pure returns (address[] memory _route) {
        _route = new address[](2);
        _route[0] = t1;
        _route[1] = t2;
    }

    function route(address t1, address t2, address t3) internal pure returns (address[] memory _route) {
        _route = new address[](3);
        _route[0] = t1;
        _route[1] = t2;
        _route[2] = t3;
    }

    function bytesToStr(bytes memory buffer) public pure returns (string memory) {
        // Fixed buffer size for hexadecimal convertion
        bytes memory converted = new bytes(buffer.length * 2);
        bytes memory _base = "0123456789abcdef";
        for (uint256 i = 0; i < buffer.length; i++) {
            converted[i * 2] = _base[uint8(buffer[i]) / _base.length];
            converted[i * 2 + 1] = _base[uint8(buffer[i]) % _base.length];
        }
        return string(abi.encodePacked("0x", converted));
    }

    function addrToStr(address a) public pure returns (string memory) {
        return bytesToStr(abi.encodePacked(a));
    }

    function boolToStr(bool b) public pure returns (string memory) {
        return b ? 'true' : 'false';
    }

    function routeToStr(address[] memory a) public pure returns (string memory t) {
        if (a.length == 0) return "[]";
        if (a.length == 1) return string.concat("[", bytesToStr(abi.encodePacked(a[0])), "]");
        t = string.concat("[", bytesToStr(abi.encodePacked(a[0])));
        for (uint i = 1; i < a.length; i++) {
            t = string.concat(t, ",", bytesToStr(abi.encodePacked(a[i])));
        }
        t = string.concat(t, "]");
    }

    function uintsToStr(uint[5] memory a) public pure returns (string memory t) {
        if (a.length == 0) return "[]";
        if (a.length == 1) return string.concat("[", vm.toString(a[0]), "]");
        t = string.concat("[", vm.toString(a[0]));
        for (uint i = 1; i < a.length; i++) {
            t = string.concat(t, ",", vm.toString(a[i]));
        }
        t = string.concat(t, "]");
    }

    function print(address[] memory a) internal view {
        for (uint i; i < a.length; ++i) {
            console.log(i, a[i]);
        }
    }
}