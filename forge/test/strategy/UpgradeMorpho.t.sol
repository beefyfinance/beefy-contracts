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
    0x3d4C4cD9Ca34741464FA3AE4f095b0c39d7BbBB4,
    0xCB7041bf0e0c3756781c3C81147A8D28C25c2033,
    0xEA1C8999C20f76aFAFCe34ED6265890EFF8b3B36,
    0x730EB1e054ad08b390E29A648DE134c35270cE72,
    0xdCEe3AE4f82Bd085fF147B87a754517d8CAafF3b
    ];

    string stratName;
    address newImpl;
    StrategyFactory factory;

    function setUp() public {
        newImpl = 0xCc17Dc7ce896ee8969118B46Ab1001bFA13e8431; //address(new StrategyMorpho());
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
            assertGe(ppsAfterUpgrade, pps[i], "Vault pps changed");

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

            if (address(strategy) == 0xCB7041bf0e0c3756781c3C81147A8D28C25c2033) {
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

        TimelockController t = TimelockController(payable(0x1c9270ac5C42E51611d7b97b1004313D52c80293));
        vm.prank(0x34fEf5DA92c59d6aC21d0A75ce90B351D0Fb6CE6);
        t.scheduleBatch(targets, values, payloads, 0x00, 0x00, 21600);
        skip(1 days);
        vm.prank(factory.keeper());
        t.executeBatch(targets, values, payloads, 0x00, 0x00);

        for (uint i; i < strats.length; i++) {
            assertGt(StrategyMorpho(payable(strats[i])).balanceOf(), bals[i]);
        }

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