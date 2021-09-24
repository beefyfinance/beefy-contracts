const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const { addressBook } = require("blockchain-addressbook");

const ethers = hardhat.ethers;

const config = {
  bifi: "0x99c409e5f62e4bd2ac142f17cafb6810b8f0baae",
  wNative: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
  treasury: "0xc3a4fdcba79DB04b4C3e352b1C467B3Ba909D84A",
  rewardPool: "0x48F4634c8383aF01BF71AefBC125eb582eb3C74D",
  unirouter: ethers.constants.AddressZero,
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

  // await hardhat.run("verify:verify", {
  //   address: implementationAddr,
  // });
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
