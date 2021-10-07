const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    QUICK: {address: QUICK},
    DAI: {address: DAI},
    ETH: {address: ETH},
    USDC: {address: USDC},
    WMATIC: {address: WMATIC},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = true;

const want = web3.utils.toChecksumAddress("0xf04adBF75cDFc5eD26eeA4bbbb991DB002036Bdd");
const rewardPool = web3.utils.toChecksumAddress("0xacb9eb5b52f495f09ba98ac96d8e61257f3dae14"); //TODO: needs to be the new one

const vaultParams = {
    mooName: "Moo Quick USDC-DAI",
    mooSymbol: "mooQuickUSDC-DAI",
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
    outputToLp0Route: [QUICK, WMATIC, USDC],
    outputToLp1Route: [QUICK, WMATIC, ETH, DAI],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}