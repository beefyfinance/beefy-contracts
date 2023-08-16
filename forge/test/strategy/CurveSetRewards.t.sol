// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

//import "forge-std/Test.sol";
import "../../../node_modules/forge-std/src/Test.sol";
import "../../../node_modules/forge-std/src/StdJson.sol";
import "../../../node_modules/@openzeppelin-4/contracts/governance/TimelockController.sol";

// Users
import "../users/VaultUser.sol";
// Interfaces
import "../interfaces/IVault.sol";
import "../interfaces/IStrategy.sol";
import "../interfaces/IERC20Like.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyConvex.sol";
import "../../../contracts/BIFI/strategies/Curve/StrategyConvexCRV.sol";

contract CurveSetRewards is Test {
    using stdJson for string;

    string s = '["0x3048F3cB8922f3b4BCD953ab5563dCc8B99Ef50E","0xE31e2e731DE87FfD0eCE2cE2f486E9095C8eBE63","0x3e349b83A3E68bdD5BB71fAB63dDE123c478FEA4","0x38930EeA3767cEd8A7Bd765F67469f66e35fC8d0","0x28d30Ff6217CeEC822F3f2Db940539350C412d8e","0x2e332BFf3664A2A37214E4770670270CB2D82DD2","0xc5A3F1fE18B3EeEcf9505B571B3EB9730560ABde","0x2A02bd17e2b2F0bB2Fc420380109EDA9B204d4B7","0xEbe9f4059Ff0D5cC2Dce85b95d03BF8aaF96446b","0x6Fe4B79Ff8f6BE2d28f05a09E59652626E64A388","0x3Ec7a4c28A18E4CB0924B7E0aDe64e72fB011F21","0x202E4449Fcd53c2485AEB1D79B2CF939b986A0c3","0xAe6f59af24C8998eDe1f85711f7C9d71d2A879F9","0x2F40AEB1A1aa6DD10A8Af0926F416d01ffD9777C","0xb4e5151e79eA386AAd13Ca65DD0E66fBF5dE5B1E","0x77c07F9f52c08c580B4D90409948644531C0150C","0x158a32914Adfbf183e8385136532F5f099BC2E44","0xcA1E160fe3CB09831407FA075660822bfe85B74C","0xB9e88B403281346F9b18D1b81c56451E74714d26","0x5a5Ec9505a6Afc77ab759811666b3E3CAbc8a2F4","0xEeE94d0E85cB79eDc34a5D362095B6BB92355dd0","0x224aaa0FdF90c5e69a10B7E058320A08cA6e81FC","0xD11C6816a2A550E330A9d1049d9C545a39974fc2","0xa5F7021e65534323a875aBf063B1AdF462b99096","0x3AdeCf9eFE2C3f5b6A7EC0e19b1c95114019ECA9","0xD26155f3B1Cd17e4dcF21209956780D7450DDA2A","0xE9E6642D271fdFa574F0b08511dd3aaCabD1481d","0xdB864FB636eA37B61D02229AebaC8b0679760BD2","0xAdcd9293F14297D23abC925008b84192b3643EbE","0x7FCE7f97E4CE6572EF99C2562A4c6b1C5903bbe1"]';
    address[] addresses;
    StrategyConvex[] strats;
    TimelockController timelock;
    uint delay;

    address devMultisig = 0x34fEf5DA92c59d6aC21d0A75ce90B351D0Fb6CE6;
    bytes setCurveSwapAmount_0 = hex'f85d44650000000000000000000000000000000000000000000000000000000000000000';
    bytes addCRV = hex'988a23e9000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000005af3107a4000000000000000000000000000000000000000000000000000000000000000002bd533a949740bb3306d119cc777fa900ba034cd52000bb8c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000';
    bytes addCVX = hex'988a23e9000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000005af3107a4000000000000000000000000000000000000000000000000000000000000000002b4e3fbd56cd56c3e72c1403e103b45db9da5b9d2b002710c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000000000000000000000';
    bytes setNativeToCrv = hex'1d4735e6000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000004ebdf703948ddcea3b11f675b4d1fba9d2414a14000000000000000000000000d533a949740bb3306d119cc777fa900ba034cd52000000000000000000000000971add32ea87f10bd192671630be3be8a11b862300000000000000000000000062b9c7356a2dc64a1969e19c23e4f579f9810aa70000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000';

    address convex_staked_cvxCRV = 0x2F40AEB1A1aa6DD10A8Af0926F416d01ffD9777C;

    function setUp() public {
        addresses = abi.decode(s.parseRaw("*"), (address[]));
        for (uint i; i < addresses.length; i++) {
            strats.push(StrategyConvex(payable(addresses[i])));
        }

        timelock = TimelockController(payable(strats[0].owner()));
        delay = timelock.getMinDelay();
        console.log(delay);
    }

    function test_setSwapAmount() external {
        timelockCall(setCurveSwapAmount_0);
    }

    function test_addCRVRewards() external {
        timelockCall(addCRV);
    }

    function test_addCVXRewards() external {
        timelockCall(addCVX);
    }

    function test_harvest() external {
        timelockCall(setCurveSwapAmount_0);
        timelockCall(addCRV);
        timelockCall(addCVX);
        for (uint i; i < strats.length; i++) {
            if (address(strats[i]) != convex_staked_cvxCRV) {
                IVault vault = IVault(strats[i].vault());
                uint ppfs = vault.getPricePerFullShare();
                strats[i].harvest();
                assertTrue(vault.getPricePerFullShare() > ppfs, "ppfs");
            }
        }
    }

    function test_cvxCrvHarvest() external {
        timelockCall(setCurveSwapAmount_0);
        timelockCall(addCRV);
        timelockCall(addCVX);
        StrategyConvexCRV strat = StrategyConvexCRV(payable(convex_staked_cvxCRV));

        vm.prank(devMultisig);
        timelock.schedule(convex_staked_cvxCRV, 0, setNativeToCrv, 0x00, 0x00, delay);
        skip(delay);
        vm.prank(strat.keeper());
        timelock.execute(convex_staked_cvxCRV, 0, setNativeToCrv, 0x00, 0x00);

        IVault vault = IVault(strat.vault());
        uint ppfs = vault.getPricePerFullShare();
        strat.harvest();
        assertTrue(vault.getPricePerFullShare() > ppfs, "ppfs");
    }

    function timelockCall(bytes memory _data) public {
        uint[] memory values = new uint[](strats.length);
        bytes[] memory data = new bytes[](strats.length);
        for (uint i; i < strats.length; i++) {
            data[i] = _data;
        }
        vm.prank(devMultisig);
        timelock.scheduleBatch(addresses, values, data, 0x00, 0x00, delay);

        skip(delay);

        vm.prank(strats[0].keeper());
        timelock.executeBatch(addresses, values, data, 0x00, 0x00);
    }
}