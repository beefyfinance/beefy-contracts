const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    NEXO: {address: NEXO},
    ETH: {address: ETH},
    QUICK: {address: QUICK},
    WMATIC: {address: WMATIC},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x10062ec62c0be26cc9e2f50a1cf784a89ded075f");
const rewardPool = web3.utils.toChecksumAddress("0x1476331f814c00f1d15dc6187a0eb1e1e403d745");

const vaultParams = {
    mooName: "Moo Quick NEXO-ETH",
    mooSymbol: "mooQuickNEXO-ETH",
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
    outputToLp0Route: [QUICK, ETH, NEXO],
    outputToLp1Route: [QUICK, ETH],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}