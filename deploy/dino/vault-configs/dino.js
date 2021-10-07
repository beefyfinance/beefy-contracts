const {addressBook} = require("blockchain-addressbook");
const {web3} = require("hardhat");

const {
    DINO: {address: DINO},
    WMATIC: {address: WMATIC},
} = addressBook.polygon.tokens;
const {quickswap, beefyfinance} = addressBook.polygon.platforms;

const shouldVerifyOnEtherscan = true;

const want = web3.utils.toChecksumAddress(DINO);
const eternalPool = web3.utils.toChecksumAddress("0x52e7b0C6fB33D3d404b07006b006c8A8D6049C55");

const vaultParams = {
    mooName: "Moo Dino DINO",
    mooSymbol: "mooDinoDINO",
    delay: 21600,
};

const strategyParams = {
    want: want,
    rewardPool: eternalPool,
    unirouter: quickswap.router,
    strategist: "0x715Beae184768766C65D8Ed4AA6D1f6893efb542", // Qkyrie
    keeper: beefyfinance.keeper,
    beefyFeeRecipient: beefyfinance.beefyFeeRecipient,
    outputToNativeRoute: [DINO, WMATIC],
};

module.exports = {
    vaultParams: vaultParams,
    strategyParams: strategyParams,
    shouldVerifyOnEtherscan: shouldVerifyOnEtherscan
}