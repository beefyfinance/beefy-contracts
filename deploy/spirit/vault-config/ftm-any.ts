const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    FTM: {address: FTM},
    ANY: {address: ANY},
    SPIRIT: {address: SPIRIT}
} = addressBook.fantom.tokens;
const {spiritswap, beefyfinance} = addressBook.fantom.platforms;

const shouldVerifyOnEtherscan = false;

const want = web3.utils.toChecksumAddress("0x26D583028989378Cc1b7CBC023f4Ae049d5e5899");
const rewardPool = web3.utils.toChecksumAddress(spiritswap.masterchef); //TODO: needs to be the new one

const vaultParams = {
    mooName: "Moo Spirit ANY-FTM",
    mooSymbol: "mooSpiritANY-FTM",
    delay: 21600,
};

const strategyParams = {
    want: want,
    poolId: 18,
    rewardPool: rewardPool,
    unirouter: spiritswap.router,
    strategist: "0x715Beae184768766C65D8Ed4AA6D1f6893efb542", // Qkyrie
    keeper: beefyfinance.keeper,
    beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
    outputToNativeRoute: [SPIRIT, FTM],
    outputToLp0Route: [SPIRIT, FTM],
    outputToLp1Route: [SPIRIT, FTM, ANY],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}