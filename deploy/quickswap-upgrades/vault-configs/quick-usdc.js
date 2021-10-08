const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    QUICK: {address: QUICK},
    ETH: {address: ETH},
    USDC: {address: USDC},
    WMATIC: {address: WMATIC},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x1f1e4c845183ef6d50e9609f16f6f9cae43bc9cb");
const rewardPool = web3.utils.toChecksumAddress("0x939290ed45514e82900ba767bbcfa38ee1067039");

const vaultParams = {
    mooName: "Moo Quick QUICK-USDC",
    mooSymbol: "mooQuickQUICK-USDC",
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
    outputToLp0Route: [QUICK, USDC], //USDC
    outputToLp1Route: [QUICK], //QUICK
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}