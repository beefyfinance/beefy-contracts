import { CommonConfig, LpConfig, ChefConfig } from "./types";
import { addressBook, ChainId } from "blockchain-addressbook";
const { polygon } = addressBook;

const config:Record<string,CommonConfig & LpConfig & ChefConfig> = {
    "mai-usdc-mimatic": {
        chainId: ChainId.polygon,
        platform: "Mai",
        chef: polygon.platforms.mai.chef,
        poolId: 1,
        unirouter: polygon.platforms.quickswap.router,
        strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
        want: "0x160532D2536175d65C03B97b0630A9802c274daD",
        withdrawalFee:0,
        lp0: polygon.tokens.USDC,
        lp1: polygon.tokens.miMATIC,
        outputToLp0Route: [
            polygon.tokens.QI.address,
            polygon.tokens.miMATIC.address,
            polygon.tokens.USDC.address
        ],
        outputToLp1Route: [
            polygon.tokens.QI.address,
            polygon.tokens.miMATIC.address
        ],
        outputToNativeRoute: [
            polygon.tokens.QI.address,
            polygon.tokens.QUICK.address,
            polygon.tokens.WMATIC.address
        ],
    },
    "mai-qi-mimatic": {
        chainId: ChainId.polygon,
        platform: "Mai",
        chef: polygon.platforms.mai.chef,
        poolId: 2,
        unirouter: polygon.platforms.quickswap.router,
        strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
        want: "0x7AfcF11F3e2f01e71B7Cc6b8B5e707E42e6Ea397",
        withdrawalFee:0,
        lp0: polygon.tokens.QI,
        lp1: polygon.tokens.miMATIC,
        outputToLp0Route: [],
        outputToLp1Route: [
            polygon.tokens.QI.address,
            polygon.tokens.miMATIC.address
        ],
        outputToNativeRoute: [
            polygon.tokens.QI.address,
            polygon.tokens.QUICK.address,
            polygon.tokens.WMATIC.address
        ],
    },
};
export default config;