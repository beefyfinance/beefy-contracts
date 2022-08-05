const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
import { addressBook } from "blockchain-addressbook";

const ethers = hardhat.ethers;

const {
  platforms: { stella, beefyfinance },
  tokens: {
    USDC: { address: USDC },
    GLMR: { address: GLMR },
    BIFI: { address: BIFI }
  },
} = addressBook.cronos;

const addressZero = ethers.constants.AddressZero,

const config = {
  treasury: beefyfinance.treasuryMultisig,
  rewardPool: beefyfinance.rewardPool,
  unirouter: vvs.router,
  bifi: BIFI,
  wNative: CRO,
  stable: USDC,
  bifiRoute: [CRO, BIFI],
  stableRoute: [CRO, USDC],
  splitTreasury: false,
  treasuryFee: 640
};

async function main() {
  await hardhat.run("compile");

  const deployer = await ethers.getSigner();
  const provider = deployer.provider;

  const BeefyFeeBatch = await ethers.getContractFactory("BeefyFeeBatchV3");

  const batcher = await upgrades.deployProxy(BeefyFeeBatch,  [
    config.bifi,
    config.wNative,
    config.stable,
    config.treasury,
    config.rewardPool,
    config.unirouter,
    config.bifiRoute, 
    config.stableRoute, 
    config.splitTreasury,
    config.treasuryFee
  ]
 );
  await batcher.deployed();

  const implementationAddr = await getImplementationAddress(provider, batcher.address);
  console.log("Deployed to:", batcher.address);
  console.log(`Deployed implementation at ${implementationAddr}`);

 
  console.log(`Verifing implementation`);
  await hardhat.run("verify:verify", {
    address: implementationAddr,
    constructorArguments: [
    ]
  })

}



main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
