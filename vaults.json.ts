import { addressBook } from "blockchain-addressbook";
import { type } from "os";

const { miMATIC: {address: miMATIC}, USDC: {address: USDC}, QUICK: { address: QUICK }, WMATIC: { address: WMATIC }, ETH: { address: ETH } } = addressBook.polygon.tokens;
const { quickswap, beefyfinance } = addressBook.polygon.platforms;

type VaultConfig = {
    chain:Number,
    platform:String,
    vaultContract:String,
    strategyContract:String,
    want:String,
    rewardPool:String,
    unirouter:String,
    strategist:String,
    lp0: {
        name:String,
        addr:String,
    },
    lp1: {
        name:String,
        addr:String,
    },
    outputToNativeRoute:String[],
    outputToLp0Route:String[],
    outputToLp1Route:String[],
}

const config:Record<string,VaultConfig> = {
    "quick-mimatic-usdc": {
        chain: 137,
        platform: "Quick",
        vaultContract: "BeefyVaultV6",
        strategyContract: "StrategyCommonRewardPoolLP",
        want: "0x160532D2536175d65C03B97b0630A9802c274daD",
        rewardPool: "0x1fdDd7F3A4c1f0e7494aa8B637B8003a64fdE21A",
        unirouter: quickswap.router,
        strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
        lp0: {
            name: "USDC",
            addr: USDC,
        },
        lp1: {
            name: "miMATIC",
            addr: miMATIC,
        },
        outputToNativeRoute: [QUICK, WMATIC],
        outputToLp0Route: [QUICK, USDC],
        outputToLp1Route: [QUICK, USDC, miMATIC],
    }
};
export default config;