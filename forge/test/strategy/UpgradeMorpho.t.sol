// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

// Interfaces
import "../../../node_modules/forge-std/src/Test.sol";
import "../interfaces/IERC20Like.sol";
import "../interfaces/IVault.sol";
import "../users/VaultUser.sol";
import "../utils/Utils.sol";
import {StrategyFactory} from "../../../contracts/BIFI/infra/StrategyFactory.sol";
import {StrategyMorpho} from "../../../contracts/BIFI/strategies/Morpho/StrategyMorpho.sol";
import {TimelockController} from "../../../node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol";

contract UpgradeMorpho is Test {

    address[] strats = [
    0xC02ceF879331834a7823f2AfAD6a1DF7d9DB6C05,
    0xD612Bb264F973076ea934f2080BAc1fC2e7d8238,
    0x38233654FB0843c8024527682352A5d41E7f7324,
    0xbFC232804610D7C02B9E4b271f0935a99e36d4fb,
    0x5Ac5BDb5DCe41f6fE7cb78bA7ad53367B98749B8,
    0xD42b606021305024A40fB77B04eBe7DDD189Df48
    ];
//    address newImpl = address(new StrategyMorpho());
    address newImpl = 0x5cf364aFD3ebb8a1964BeF44cB60847267E81DBF;
    address multisig = 0x6FfaCA7C3B38Ec2d631D86e15f328ee6eF6C6226;

    string stratName;
    StrategyFactory factory;

    function setUp() public {
        StrategyMorpho strategy = StrategyMorpho(payable(strats[0]));
        factory = StrategyFactory(address(strategy.factory()));
        stratName = strategy.stratName();
    }

    function test_upgrade() external {
        uint[] memory vaultBalance = new uint[](strats.length);
        uint[] memory pps = new uint[](strats.length);
        for (uint i; i < strats.length; i++) {
            StrategyMorpho strategy = StrategyMorpho(payable(strats[i]));
            IVault vault = IVault(strategy.vault());
            vaultBalance[i] = vault.balance();
            pps[i] = vault.getPricePerFullShare();

//            vm.prank(strategy.keeper());
//            strategy.panic();
        }

        console.log("Upgrade strat");
        vm.prank(factory.owner());
        factory.upgradeTo(stratName, newImpl);
        assertEq(newImpl, factory.getImplementation(stratName), "!upgraded");

        uint snapshotId = vm.snapshotState();

        for (uint i; i < strats.length; i++) {
            vm.revertToState(snapshotId);
            StrategyMorpho strategy = StrategyMorpho(payable(strats[i]));
            IVault vault = IVault(strategy.vault());
            console.log();
            console.log(vault.name(), vault.symbol());
            VaultUser user = new VaultUser();
            uint wantAmount = vault.totalSupply();
            deal(vault.want(), address(user), wantAmount);

            if (strategy.paused()) {
                console.log("Unpause");
                vm.prank(strategy.keeper());
                strategy.unpause();
            }

            vm.expectRevert("Ownable: caller is not the owner");
            strategy.setStoredBalance();
            vm.prank(strategy.owner());
            strategy.setStoredBalance();

            uint vaultBalAfterUpgrade = vault.balance();
            uint ppsAfterUpgrade = vault.getPricePerFullShare();
            assertEq(vaultBalAfterUpgrade, vaultBalance[i], "Vault balance changed");
            assertEq(ppsAfterUpgrade, pps[i], "Vault pps changed");

            skip(1 days);
            console.log("Harvest");
            strategy.harvest();
            skip(1 days);
            uint256 vaultBalAfterHarvest = vault.balance();
            uint256 ppsAfterHarvest = vault.getPricePerFullShare();
            console.log("Balance", vaultBalAfterUpgrade, vaultBalAfterHarvest);
            console.log("PPS", ppsAfterUpgrade, ppsAfterHarvest);
            assertGt(vaultBalAfterHarvest, vaultBalAfterUpgrade, "Harvested 0");
            assertGt(ppsAfterHarvest, ppsAfterUpgrade, "Expected ppsAfterHarvest > upgraded");

//            if (address(strategy) == 0xCB7041bf0e0c3756781c3C81147A8D28C25c2033) {
            if (address(strategy) == 0x38233654FB0843c8024527682352A5d41E7f7324) {
                console.log("Panic");
                vm.startPrank(strategy.keeper());
                vm.expectRevert(bytes4(hex'4323a555'));
                strategy.panic();
                vm.stopPrank();
            } else {
                console.log("Panic");
                vm.prank(strategy.keeper());
                strategy.panic();

                console.log("Unpause");
                vm.prank(strategy.keeper());
                strategy.unpause();
            }

            console.log("Deposit");
            user.approve(vault.want(), address(vault), wantAmount);
            user.depositAll(vault);

            console.log("Withdrawal");
            user.withdrawAll(vault);
            uint userBal = IERC20Like(vault.want()).balanceOf(address(user));
            console.log("User balance after withdrawal", userBal);
            assertGt(userBal, wantAmount * 99 / 100, "Expected balance increase");
        }
    }

    function test_multisig() public {
        TimelockController t = TimelockController(payable(factory.owner()));

        uint[] memory bals = new uint[](strats.length);
        for (uint i; i < strats.length; i++) {
            StrategyMorpho strategy = StrategyMorpho(payable(strats[i]));
            bals[i] = strategy.balanceOf() + strategy.lockedProfit();
        }

        address[] memory targets = new address[](strats.length + 1);
        uint[] memory values = new uint[](targets.length);
        bytes[] memory payloads = new bytes[](targets.length);

        bytes memory upgradeCall = abi.encodeCall(StrategyFactory.upgradeTo, (stratName, newImpl));
        bytes memory setStoredBalance = abi.encode(StrategyMorpho.setStoredBalance.selector);

        targets[0] = address(factory);
        payloads[0] = upgradeCall;
        for (uint i = 1; i <= strats.length; i++) {
            targets[i] = strats[i-1];
            payloads[i] = setStoredBalance;
        }

        vm.prank(multisig);
        t.scheduleBatch(targets, values, payloads, 0x00, 0x00, 21600);
        skip(1 days);
        vm.prank(factory.keeper());
        t.executeBatch(targets, values, payloads, 0x00, 0x00);

        for (uint i; i < strats.length; i++) {
            assertGt(StrategyMorpho(payable(strats[i])).balanceOf(), bals[i]);
        }

        console.log("owner:", address(t));
        console.log("targets:");
        console.log(Utils.addrToStr(targets));
        console.log("payloads:");
        string memory payloadsStr = string.concat("[", Utils.bytesToStr(payloads[0]));
        for (uint i=1; i < payloads.length; i++) {
            payloadsStr = string.concat(payloadsStr, ",", Utils.bytesToStr(payloads[1]));
        }
        payloadsStr = string.concat(payloadsStr, "]");
        console.log(payloadsStr);
    }
}