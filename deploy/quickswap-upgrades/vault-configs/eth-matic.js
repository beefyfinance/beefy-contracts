const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    QUICK: {address: QUICK},
    ETH: {address: ETH},
    WMATIC: {address: WMATIC},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0xadbF1854e5883eB8aa7BAf50705338739e558E5b");
const rewardPool = web3.utils.toChecksumAddress("0x4b678ca360c5f53a2b0590e53079140f302a9dcd");

const vaultParams = {
    mooName: "Moo Quick ETH-MATIC",
    mooSymbol: "mooQuickETH-MATIC",
    delay: 21600,
};

const strategyParams = {
    want: want,
    rewardPool: rewardPool,
    unirouter: quickswap.router,
    strategist: "0x010da5ff62b6e45f89fa7b2d8ced5a8b5754ec1b",
    keeper: beefyfinance.keeper,
    beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
    outputToNativeRoute: [QUICK, WMATIC],
    outputToLp0Route: [QUICK, WMATIC],
    outputToLp1Route: [QUICK, ETH],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}