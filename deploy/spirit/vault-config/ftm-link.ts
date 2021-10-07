const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    FTM: {address: FTM},
    LINK: {address: LINK},
    SPIRIT: {address: SPIRIT}
} = addressBook.fantom.tokens;
const {spiritswap, beefyfinance} = addressBook.fantom.platforms;

const shouldVerifyOnEtherscan = true;

const want = web3.utils.toChecksumAddress("0xd061c6586670792331E14a80f3b3Bb267189C681");
const rewardPool = web3.utils.toChecksumAddress(spiritswap.masterchef); //TODO: needs to be the new one

const vaultParams = {
    mooName: "Moo Spirit LINK-FTM",
    mooSymbol: "mooSpiritLINK-FTM",
    delay: 21600,
};

const strategyParams = {
    want: want,
    poolId: 11,
    rewardPool: rewardPool,
    unirouter: spiritswap.router,
    strategist: "0x715Beae184768766C65D8Ed4AA6D1f6893efb542", // Qkyrie
    keeper: beefyfinance.keeper,
    beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
    outputToNativeRoute: [SPIRIT, FTM],
    outputToLp0Route: [SPIRIT, FTM],
    outputToLp1Route: [SPIRIT, FTM, LINK],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}