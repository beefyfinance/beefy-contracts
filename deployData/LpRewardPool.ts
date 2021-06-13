import { CommonConfig, LpConfig, RewardPoolConfig } from "./types";
import { addressBook, ChainId } from "blockchain-addressbook";
const { polygon } = addressBook;

const config:Record<string,CommonConfig & LpConfig & RewardPoolConfig> = {
    "quick-mimatic-usdc": {
        chainId: ChainId.polygon,
        platform: "Quick",
        rewardPool: "0x1fdDd7F3A4c1f0e7494aa8B637B8003a64fdE21A",
        unirouter: polygon.platforms.quickswap.router,
        strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
        want: "0x160532D2536175d65C03B97b0630A9802c274daD",
        lp0: polygon.tokens.USDC,
        lp1: polygon.tokens.miMATIC,
        outputToLp0Route: [
            polygon.tokens.QUICK.address,
            polygon.tokens.USDC.address
        ],
        outputToLp1Route: [
            polygon.tokens.QUICK.address,
            polygon.tokens.USDC.address,
            polygon.tokens.miMATIC.address
        ],
        outputToNativeRoute: [
            polygon.tokens.QUICK.address,
            polygon.tokens.WMATIC.address
        ],
    },
};
export default config;