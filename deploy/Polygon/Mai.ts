import deployVault from "../../deployScripts/deployVault";
import { StrategyCommonChefLPConfig, VaultConfig } from "../../deployData/types";
import { addressBook, ChainId } from "blockchain-addressbook";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
const { polygon } = addressBook;

const deployFunc:DeployFunction = async function(hre: HardhatRuntimeEnvironment) {

    // mai-usdc-mimatic
    await deployVault(hre, VaultConfig(StrategyCommonChefLPConfig, {
        chainId: ChainId.polygon,
        platform: "Mai",
        chef: polygon.platforms.mai.chef,
        poolId: 1,
        unirouter: polygon.platforms.quickswap.router,
        strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
        withdrawalFee: 0,
        want: "0x160532D2536175d65C03B97b0630A9802c274daD",
        outputToLp0Route: [
            polygon.tokens.QI,
            polygon.tokens.miMATIC,
            polygon.tokens.USDC
        ],
        outputToLp1Route: [
            polygon.tokens.QI,
            polygon.tokens.miMATIC
        ],
        outputToNativeRoute: [
            polygon.tokens.QI,
            polygon.tokens.QUICK,
            polygon.tokens.WMATIC
        ],
    }));

    // mai-qi-mimatic
    await deployVault(hre, VaultConfig(StrategyCommonChefLPConfig, {
        chainId: ChainId.polygon,
        platform: "Mai",
        chef: polygon.platforms.mai.chef,
        poolId: 2,
        unirouter: polygon.platforms.quickswap.router,
        strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
        withdrawalFee: 0,
        want: "0x7AfcF11F3e2f01e71B7Cc6b8B5e707E42e6Ea397",
        outputToLp0Route: [
            polygon.tokens.QI
        ],
        outputToLp1Route: [
            polygon.tokens.QI,
            polygon.tokens.miMATIC
        ],
        outputToNativeRoute: [
            polygon.tokens.QI,
            polygon.tokens.QUICK,
            polygon.tokens.WMATIC
        ],
    }));
};
deployFunc.tags = ['Polygon','Mai'];
export default deployFunc;