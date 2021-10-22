const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const { addressBook } = require("blockchain-addressbook");

const ethers = hardhat.ethers;

const chain = "fantom";
const a = addressBook[chain].platforms.beefyfinance.beefyFeeRecipient;

const config = {
  bifi: addressBook[chain].tokens.BIFI.address,
  wNative: addressBook[chain].tokens.WNATIVE.address,
  treasury: addressBook[chain].platforms.beefyfinance.treasury,
  rewardPool: addressBook[chain].platforms.beefyfinance.rewardPool,
  unirouter: "0xF491e7B69E4244ad4002BC14e878a34207E38c29",
};

async function main() {
  await hardhat.run("compile");

  const [signer] = await ethers.getSigners();
  const provider = signer.provider;

  const BeefyFeeBatch = await ethers.getContractFactory("BeefyFeeBatchV2");
  const batcher = await upgrades.deployProxy(BeefyFeeBatch, [
    config.bifi,
    config.wNative,
    config.treasury,
    config.rewardPool,
    config.unirouter,
  ]);

  await batcher.deployed();

  const implementationAddr = await getImplementationAddress(provider, batcher.address);

  console.log(`Deployed proxy at ${batcher.address}`);
  console.log(`Deployed implementation at ${implementationAddr}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
