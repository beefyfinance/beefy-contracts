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
import "../interfaces/IUniV3Quoter.sol";
import "../../../contracts/BIFI/vaults/BeefyVaultV7.sol";
import "../../../contracts/BIFI/interfaces/common/IERC20Extended.sol";
import "../../../contracts/BIFI/strategies/Common/StratFeeManager.sol";
import "../../../contracts/BIFI/strategies/degens/StrategyChronosLP.sol";
import "../../../contracts/BIFI/utils/AlgebraUtils.sol";
import "./BaseStrategyTest.t.sol";
import "../vault/util/HardhatNetworkManager.sol";

contract StrategyChronosLPTest is BaseStrategyTest {

    IStrategy constant PROD_STRAT = IStrategy(0x6677c03B2c7Da09dfbD869daeec3ccFd4eCC4B5F);
    address constant native = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant output = 0x15b2fb8f08E4Ac1Ce019EADAe02eE92AeDF06851;
    address constant unirouter = 0xE708aA9E887980750C040a6A2Cb901c37Aa34f3b;
    address constant wusdr = 0xDDc0385169797937066bBd8EF409b5B3c0dFEB52;
    address constant usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant arb = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address constant bifi = 0x99C409E5f62E4bd2AC142f17caFb6810B8F0BAAE;

    // WETH-BIFI
    address constant want = 0x04c106eddDBe89f2Ed983f52020F33D126fA544b;
    address constant rewardPool = 0xbD0cF21c20B5eb38B30e00f32893A80b5D823806;
    function routes() internal pure returns(
        ISolidlyRouter.Routes[] memory outputToNative,
        ISolidlyRouter.Routes[] memory outputToLp0,
        ISolidlyRouter.Routes[] memory outputToLp1
    ) {
        outputToNative = new ISolidlyRouter.Routes[](1);
        outputToNative[0] = ISolidlyRouter.Routes(output, native, false);

        outputToLp0 = new ISolidlyRouter.Routes[](1);
        outputToLp0[0] = ISolidlyRouter.Routes(output, native, false);

        outputToLp1 = new ISolidlyRouter.Routes[](2);
        outputToLp1[0] = ISolidlyRouter.Routes(output, native, false);
        outputToLp1[1] = ISolidlyRouter.Routes(native, bifi, false);
    }

    IVault vault;
    StrategyChronosLP strategy;
    VaultUser user;
    uint256 wantAmount = 50000 ether;

    function setUp() public {
        user = new VaultUser();
        address vaultAddress = vm.envOr("VAULT", address(0));
        if (vaultAddress != address(0)) {
            vault = IVault(vaultAddress);
            strategy = StrategyChronosLP(vault.strategy());
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
            strategy = new StrategyChronosLP();
            vaultV7.initialize(IStrategyV7(address(strategy)), "TestVault", "testVault", 0);
            (ISolidlyRouter.Routes[] memory outputToNative, ISolidlyRouter.Routes[] memory outputToLp0, ISolidlyRouter.Routes[] memory outputToLp1) = routes();
            strategy.initialize(want, rewardPool, outputToNative, outputToLp0, outputToLp1, commons);
        }

        deal(vault.want(), address(user), wantAmount);
        initBase(vault, IStrategy(address(strategy)));
    }

}