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
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "../../../contracts/BIFI/strategies/Common/StrategyCommonSolidlyRewardPool.sol";
import "./BaseStrategyTest.t.sol";
import "../vault/util/AddressBook.sol";

contract StrategyPearl is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0xA8c0c2E089b8606f5bC591C4980106E46c329D68);
    address constant native = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address constant output = 0x7238390d5f6F64e67c3211C343A410E2A3DEc142;
    address constant usdc = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address constant usdr = 0xb5DFABd7fF7F83BAB83995E72A52B97ABb7bcf63;
    address constant dai = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address constant unirouter = 0xda822340F5E8216C277DBF66627648Ff5D57b527;

    // wUSDR-USDR
    address constant want = 0x10E1b58B3C93890D04D539b5f39Aa4Df27A362b2;
    address constant gauge = 0xa9d0fb2581DdD3783853fB3Fda9B296a2c7a0734;
    address constant lp0 = 0xAF0D9D65fC54de245cdA37af3d18cbEc860A4D4b;
    function routes() internal pure returns(
        ISolidlyRouter.Routes[] memory outputToNative,
        ISolidlyRouter.Routes[] memory outputToLp0,
        ISolidlyRouter.Routes[] memory outputToLp1
    ) {
        outputToNative = new ISolidlyRouter.Routes[](2);
        outputToNative[0] = ISolidlyRouter.Routes(output, usdr, false);
        outputToNative[1] = ISolidlyRouter.Routes(usdr, native, false);

        outputToLp0 = new ISolidlyRouter.Routes[](2);
        outputToLp0[0] = ISolidlyRouter.Routes(output, usdr, false);
        outputToLp0[1] = ISolidlyRouter.Routes(usdr, lp0, false);

        outputToLp1 = new ISolidlyRouter.Routes[](1);
        outputToLp1[0] = ISolidlyRouter.Routes(output, usdr, false);
    }

    IVault vault;
    StrategyCommonSolidlyRewardPoolLP strategy;
    VaultUser user;
    uint256 wantAmount = 50000 ether;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyCommonSolidlyRewardPoolLP(vault.strategy());
            console.log("Testing vault at", vaultAddress);
            console.log(vault.name(), vault.symbol());
        } else {
            BeefyVaultV7 vaultV7 = new BeefyVaultV7();
            vault = IVault(address(vaultV7));

            StratFeeManagerInitializable.CommonAddresses memory commons = StratFeeManagerInitializable.CommonAddresses({
                vault: address(vault),
                unirouter: unirouter,
                keeper: PROD_STRAT.keeper(),
                strategist: address(user),
                beefyFeeRecipient: PROD_STRAT.beefyFeeRecipient(),
                beefyFeeConfig: PROD_STRAT.beefyFeeConfig()
            });
            strategy = new StrategyCommonSolidlyRewardPoolLP();
            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
            (ISolidlyRouter.Routes[] memory outputToNative, ISolidlyRouter.Routes[] memory outputToLp0, ISolidlyRouter.Routes[] memory outputToLp1) = routes();
            strategy.initialize(want, gauge, commons, outputToNative, outputToLp0, outputToLp1);
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }
}