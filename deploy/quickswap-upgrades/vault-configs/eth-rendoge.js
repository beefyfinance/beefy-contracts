const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    QUICK: {address: QUICK},
    WMATIC: {address: WMATIC},
    ETH: {address: ETH},
    renDOGE: {address: renDOGE},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0xab1403de66519b898b38028357b74df394a54a37");
const rewardPool = web3.utils.toChecksumAddress("0x16043947b496a5b31932bcf9f41dd66880ff2bb7");

const vaultParams = {
    mooName: "Moo Quick ETH-renDOGE",
    mooSymbol: "mooQuickETH-renDOGE",
    delay: 21600,
};

const strategyParams = {
    want: want,
    rewardPool: rewardPool,
    unirouter: quickswap.router,
    strategist: "0x324dee9b7bb1294c6fcf71f0841a1e5aefd19520", // TODO
    keeper: beefyfinance.keeper,
    beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
    outputToNativeRoute: [QUICK, WMATIC],
    outputToLp0Route: [QUICK, ETH],
    outputToLp1Route: [QUICK, ETH, renDOGE],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}