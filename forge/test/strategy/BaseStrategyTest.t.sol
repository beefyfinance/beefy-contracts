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
import "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import "../../../contracts/BIFI/interfaces/beefy/IStrategyFactory.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManagerInitializable.sol";

abstract contract BaseStrategyTest is Test {

    IVault internal vault;
    IStrategy private strategy;
    IERC20Like internal want;
    VaultUser internal user;
    uint internal wantAmount = 50000 ether;
    uint internal delay = 1 days;
    address internal a0 = address(0);
    bool internal dealWithAdjust = false;

    function setUp() public {
        user = new VaultUser();
        wantAmount = vm.envOr("AMOUNT", wantAmount);
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = IStrategy(createStrategy(vault.strategy()));
            console.log("Testing vault at", vaultAddress);
            console.log(vault.name(), vault.symbol());
        } else {
            bytes memory _default = '';
            bytes memory initData = vm.envOr("INIT_DATA", _default);
            if (initData.length > 0) {
                BeefyVaultV7 vaultV7 = new BeefyVaultV7();
                vault = IVault(address(vaultV7));

                address factoryAddress = vm.envOr("FACTORY", address(0));
                string memory stratName = '';
                stratName = vm.envOr("NAME", stratName);
                if (factoryAddress != address(0) && bytes(stratName).length > 0) {
                    console.log("Create strategy via proxy factory");
                    address newStrat = IStrategyFactory(factoryAddress).createStrategy(stratName);
                    strategy = IStrategy(createStrategy(newStrat));
                } else {
                    strategy = IStrategy(createStrategy(address(0)));
                }
                vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);

                (bool success,) = address(strategy).call(initData);
                assertTrue(success, "Strategy initialize not success");

                strategy.setVault(address(vault));
                assertEq(strategy.vault(), address(vault), "Vault not set");
            } else {
                strategy = IStrategy(createStrategy(address(0)));
                if (strategy.vault() == address(0)) {
                    BeefyVaultV7 vaultV7 = new BeefyVaultV7();
                    vault = IVault(address(vaultV7));
                    vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
                    strategy.setVault(address(vault));
                } else {
                    vault = IVault(strategy.vault());
                }
            }

            address callTarget = vm.envOr("CALL_TARGET", address(0));
            bytes memory callData = vm.envOr("CALL_DATA", _default);
            if (callData.length > 0) {
                vm.prank(strategy.keeper());
                (bool success,) = callTarget.call(callData);
                assertTrue(success, "Call not success");
            }

            console.log("Want", IERC20Extended(strategy.want()).symbol());
        }

        want = IERC20Like(vault.want());
        deal(vault.want(), address(user), wantAmount, dealWithAdjust);
    }

    function createStrategy(address _impl) internal virtual returns (address);

    function beforeHarvest() internal virtual {}

    function test_depositAndWithdraw() public virtual {
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

    function test_depositWithHod() external virtual {
        _depositIntoVault(user, wantAmount);
        uint pps = vault.getPricePerFullShare();
        assertGe(pps, 1e18, "Initial pps < 1");
        assertGe(vault.balance(), wantAmount, "Vault balance < wantAmount");

        console.log("setHarvestOnDeposit true");
        vm.prank(strategy.keeper());
        strategy.setHarvestOnDeposit(true);
        skip(delay);
        deal(vault.want(), address(user), wantAmount, dealWithAdjust);

        beforeHarvest();
        // trigger harvestOnDeposit
        _depositIntoVault(user, wantAmount);
        // in case of lockedProfit harvested balance is not available right away
        skip(delay);
        assertGt(vault.getPricePerFullShare(), pps, "Not harvested");
        uint vaultBal = vault.balance();

        console.log("Withdrawing all");
        user.withdrawAll(vault);

        uint wantBalanceFinal = want.balanceOf(address(user));
        console.log("Final user want balance", wantBalanceFinal);
        assertLe(wantBalanceFinal, vaultBal, "wantBalanceFinal > vaultBal");
        assertEq(vault.balance(), vaultBal - wantBalanceFinal, "vaultBal != vaultBal - wantBalanceFinal");
    }

    function test_harvest() external virtual {
        uint wantBalBefore = want.balanceOf(address(user));
        _depositIntoVault(user, wantAmount);
        uint vaultBalance = vault.balance();
        assertGe(vaultBalance, wantAmount, "Vault balance < wantAmount");

        bool stratHoldsWant = strategy.balanceOfPool() == 0;
        uint pps = vault.getPricePerFullShare();
        uint lastHarvest = strategy.lastHarvest();

        skip(delay);
        beforeHarvest();
        console.log("Harvesting vault");
        strategy.harvest();

        // in case of lockedProfit harvested balance is not available right away
        skip(delay);

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
        assertGt(wantBalAfterWithdrawal, wantBalBefore * 99 / 100, "wantBalAfterWithdrawal too small");

        console.log("Deposit all");
        user.depositAll(vault);
        uint wantBalFinal = want.balanceOf(address(user));
        uint vaultBalFinal = vault.balance();
        uint balOfPoolFinal = strategy.balanceOfPool();
        uint balOfWantFinal = strategy.balanceOfWant();
        assertEq(wantBalFinal, 0, "wantBalFinal != 0");
        assertGt(vaultBalFinal, vaultBalAfterHarvest * 99 / 100, "vaultBalFinal != vaultBalAfterHarvest");

        // strategy holds want without depositing into farming pool
        if (stratHoldsWant) {
            assertEq(balOfPoolFinal, 0, "balOfPoolFinal != 0");
            assertEq(balOfWantFinal, vaultBalFinal, "balOfWantFinal != vaultBalFinal");
        } else {
            assertEq(balOfPoolFinal, vaultBalFinal, "balOfPoolFinal != vaultBalFinal");
            assertEq(balOfWantFinal, 0, "balOfWantFinal != 0");
        }
    }

    /*         */
    /* Helpers */
    /*         */

    function _depositIntoVault(VaultUser user_, uint amount) internal {
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

    function print(address[] memory a) internal pure {
        for (uint i; i < a.length; ++i) {
            console.log(i, a[i]);
        }
    }
}