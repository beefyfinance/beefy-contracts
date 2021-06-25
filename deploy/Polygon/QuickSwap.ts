import deployVault from "../../deployScripts/deployVault";
import { StrategyCommonRewardPoolLPConfig, VaultConfig } from "../../deployData/types";
import { addressBook, ChainId } from "blockchain-addressbook";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
const { polygon } = addressBook;

export default async function(this:DeployFunction, hre: HardhatRuntimeEnvironment) {
    this.tags = ['Polygon','QuickSwap'];

    // quick-rusd-usdc
    await deployVault(hre, VaultConfig(StrategyCommonRewardPoolLPConfig, {
        chainId: ChainId.polygon,
        platform: "QuickSwap",
        rewardPool: "0x5C1186F784A4fEFd53Dc40c492b02dEEd97E7944",
        unirouter: polygon.platforms.quickswap.router,
        strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
        want: "0x5EF8747d1dc4839e92283794a10d448357973aC0",
        outputToLp0Route: [
            polygon.tokens.QUICK,
            polygon.tokens.USDC
        ],
        outputToLp1Route: [
            polygon.tokens.QUICK,
            polygon.tokens.USDC,
            polygon.tokens.rUSD
        ],
        outputToNativeRoute: [
            polygon.tokens.QUICK,
            polygon.tokens.WMATIC
        ],
    }));

    // quick-eth-ramp
    await deployVault(hre, VaultConfig(StrategyCommonRewardPoolLPConfig, {
        chainId: ChainId.polygon,
        platform: "QuickSwap",
        rewardPool: "0xBD5F8b3663F5ce456c9F53B26b0f6bC3EA22B6AA",
        unirouter: polygon.platforms.quickswap.router,
        strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
        want: "0xe55739E1fEb9F9aED4Ce34830a06cA6Cc37494A0",
        outputToLp0Route: [
            polygon.tokens.QUICK,
            polygon.tokens.ETH
        ],
        outputToLp1Route: [
            polygon.tokens.QUICK,
            polygon.tokens.ETH,
            polygon.tokens.RAMP,
        ],
        outputToNativeRoute: [
            polygon.tokens.QUICK,
            polygon.tokens.WMATIC
        ],
    }));
};
