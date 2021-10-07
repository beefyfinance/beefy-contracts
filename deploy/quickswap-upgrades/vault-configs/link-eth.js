const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    QUICK: {address: QUICK},
    LINK: {address: LINK},
    ETH: {address: ETH},
    WMATIC: {address: WMATIC},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = true;

const want = web3.utils.toChecksumAddress("0x5cA6CA6c3709E1E6CFe74a50Cf6B2B6BA2Dadd67");
const rewardPool = web3.utils.toChecksumAddress("0x1b077a0586b2abd4062a39e6368e256db2f723c4");

const vaultParams = {
    mooName: "Moo Quick LINK-ETH",
    mooSymbol: "mooQuickLINK-ETH",
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
    outputToLp0Route: [QUICK, ETH, LINK],
    outputToLp1Route: [QUICK, ETH],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}