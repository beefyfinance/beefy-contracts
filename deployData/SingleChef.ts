// import { ChefConfig, CommonConfig, LpConfig, RewardPoolConfig, SingleConfig } from "./types";
// import { addressBook, ChainId } from "blockchain-addressbook";
// const {bsc} = addressBook;

// const config:Record<string,CommonConfig & SingleConfig & ChefConfig> = {
//     "iron-steel": {
//         chainId: ChainId.bsc,
//         platform: "Iron",
//         strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
//         want: bsc.tokens.STEEL,
//         chef: bsc.platforms.ironfinance.masterchef,
//         poolId: 0,
//         unirouter: bsc.platforms.pancake.router,
//         outputToNativeRoute: [bsc.tokens.BUSD.address, bsc.tokens.WBNB.address],
//         outputToWantRoute: [bsc.tokens.BUSD.address, bsc.tokens.STEEL.address]
//     },
//     "iron-dnd": {
//         chainId: ChainId.bsc,
//         platform: "Iron",
//         strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
//         want: bsc.tokens.DND,
//         chef: bsc.platforms.ironfinance.dndsinglechef,
//         poolId: 0,
//         unirouter: bsc.platforms.pancake.router,
//         outputToNativeRoute: [bsc.tokens.DND.address, bsc.tokens.WBNB.address],
//         outputToWantRoute: []
//     }
// };
// export default config;