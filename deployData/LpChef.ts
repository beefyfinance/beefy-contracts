// import { V6Config, LpConfig, ChefConfig } from "./types";
// import { addressBook, ChainId } from "blockchain-addressbook";
// const { polygon } = addressBook;

// const config:Record<string,V6Config<LpConfig> & ChefConfig> = {
//     "mai-usdc-mimatic": {
//         chainId: ChainId.polygon,
//         platform: "Mai",
//         chef: polygon.platforms.mai.chef,
//         poolId: 1,
//         unirouter: polygon.platforms.quickswap.router,
//         strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
//         withdrawalFee:0,
//         want: new LpConfig(
//             "0x160532D2536175d65C03B97b0630A9802c274daD",
//             polygon.tokens.USDC,
//             polygon.tokens.miMATIC,
//             [
//                 polygon.tokens.QI.address,
//                 polygon.tokens.miMATIC.address,
//                 polygon.tokens.USDC.address
//             ],
//             [
//                 polygon.tokens.QI.address,
//                 polygon.tokens.miMATIC.address
//             ]),
//         outputToNativeRoute: [
//             polygon.tokens.QI.address,
//             polygon.tokens.QUICK.address,
//             polygon.tokens.WMATIC.address
//         ],
//     },
//     "mai-qi-mimatic": {
//         chainId: ChainId.polygon,
//         platform: "Mai",
//         chef: polygon.platforms.mai.chef,
//         poolId: 2,
//         unirouter: polygon.platforms.quickswap.router,
//         strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
//         withdrawalFee:0,
//         want: new LpConfig(
//             "0x7AfcF11F3e2f01e71B7Cc6b8B5e707E42e6Ea397",
//             polygon.tokens.QI,
//             polygon.tokens.miMATIC,
//             [],
//             [
//                 polygon.tokens.QI.address,
//                 polygon.tokens.miMATIC.address
//             ]),
//         outputToNativeRoute: [
//             polygon.tokens.QI.address,
//             polygon.tokens.QUICK.address,
//             polygon.tokens.WMATIC.address
//         ],
//     },
//     "sushi-wbtc-ibbtc": {
//         chainId: ChainId.polygon,
//         platform: "Sushi",
//         strategy: "StrategyPolygonSushiLP",
//         chef: polygon.platforms.sushi.minichef,
//         poolId: 24,
//         unirouter: polygon.platforms.sushi.router,
//         strategist: "0x530115e78F7BC2fE235666651f9113DB9cecE5A2",
//         want: new LpConfig(
//             "0x8F8e95Ff4B4c5E354ccB005c6B0278492D7B5907",
//             polygon.tokens.WBTC,
//             polygon.tokens.ibBTC,
//             [
//                 polygon.tokens.SUSHI.address,
//                 polygon.tokens.ETH.address,
//                 polygon.tokens.WBTC.address,
//             ],
//             [
//                 polygon.tokens.SUSHI.address,
//                 polygon.tokens.ETH.address,
//                 polygon.tokens.WBTC.address,
//                 polygon.tokens.ibBTC.address,
//             ]),
//         outputToNativeRoute: [
//             polygon.tokens.SUSHI.address,
//             polygon.tokens.WMATIC.address,
//         ],
//     },
// };
// export default config;