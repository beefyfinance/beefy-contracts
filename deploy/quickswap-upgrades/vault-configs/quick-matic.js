const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    QUICK: {address: QUICK},
    WMATIC: {address: WMATIC},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x019ba0325f1988213D448b3472fA1cf8D07618d7");
const rewardPool = web3.utils.toChecksumAddress("0xdd8758ebb792c9aed3517e9e28ce03c090564da0");

const vaultParams = {
    mooName: "Moo Quick QUICK-MATIC",
    mooSymbol: "mooQuickQUICK-MATIC",
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
    outputToLp0Route: [QUICK, WMATIC],
    outputToLp1Route: [QUICK],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}