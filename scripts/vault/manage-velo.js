const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook");
const ethers = hardhat.ethers;

const {
    tokens: {
        OP: { addresss: OP },
        VELO: { address: VELO },
        ETH: { address: ETH },
        USDC: { address: USDC },
    }
  } = addressBook.optimism;

const abi = [
    'function addGauge(address _lp, address[] calldata _bribeTokens, address[] calldata _feeTokens ) external',
    'function addRewardToken(tuple[](address,address,bool)) external'
];

const route1 = [
  "0x4200000000000000000000000000000000000042",
  "0x3c8B650257cFb5f272f799F5e2b4e65093a11a05",
  false, 
]
const config = {
  routes: [route1],
  bribeTokens: ["0x4200000000000000000000000000000000000042"],
  feeTokens: ["0x4200000000000000000000000000000000000042", "0x7F5c764cBc14f9669B88837ca1490cCa17c31607"],
  lp: "0x47029bc8f5CBe3b464004E87eF9c9419a48018cd",
  beToken: "0xB0af86f18c6155CeFaE1A6D6dA35b05F176F6278",
  addTokens: true,
  addGauge: true,
};

async function main() {

  const [deployer] = await ethers.getSigners();
  const beTokenContract = new ethers.Contract(config.beToken, abi, deployer);
  
  if (config.addTokens) {
    console.log(`Setting up Reward Token`);
    let tx  = await beTokenContract.addRewardToken(config.routes);
    tx = await tx.wait();
    console.log(`Token set up`);
  }

  if (config.addGauge) {
    console.log(`Setting up Gauge`);
    let tx  = await beTokenContract.addGauge(config.lp, config.bribeTokens, config.feeTokens);
    tx = await tx.wait();
    console.log(`Gauge set up: ${config.lp}`);
  }


}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });