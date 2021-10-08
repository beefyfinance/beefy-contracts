const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    QUICK: {address: QUICK},
    WATCH: {address: WATCH},
    WMATIC: {address: WMATIC},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x8000fe11cffa3ced146d98f091d95c9bc2c55c97");
const rewardPool = web3.utils.toChecksumAddress("0x4f5f46Db08D28b7c6A96653B7C4BdB8a209c6331");

const vaultParams = {
    mooName: "Moo Quick WATCH-QUICK",
    mooSymbol: "mooQuickWATCH-QUICK",
    delay: 21600,
};

const strategyParams = {
    want: want,
    rewardPool: rewardPool,
    unirouter: quickswap.router,
    strategist: "0x715Beae184768766C65D8Ed4AA6D1f6893efb542", // Qkyrie
    keeper: beefyfinance.keeper,
    beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
    outputToNativeRoute: [QUICK, WMATIC],
    outputToLp0Route: [QUICK, WATCH],
    outputToLp1Route: [QUICK],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}