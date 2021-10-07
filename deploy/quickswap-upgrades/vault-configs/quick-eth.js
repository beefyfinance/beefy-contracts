const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    QUICK: {address: QUICK},
    ETH: {address: ETH},
    WMATIC: {address: WMATIC},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x1Bd06B96dd42AdA85fDd0795f3B4A79DB914ADD5");
const rewardPool = web3.utils.toChecksumAddress("0x5ce139242c77fc31479e5329626fef736ac8cebe"); //TODO: needs to be the new one

const vaultParams = {
    mooName: "Moo Quick QUICK-ETH",
    mooSymbol: "mooQuickQUICK-ETH",
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
    outputToLp0Route: [QUICK, ETH],
    outputToLp1Route: [QUICK],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}