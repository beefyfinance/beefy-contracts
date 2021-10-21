const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const { addressBook } = require("blockchain-addressbook");

const ethers = hardhat.ethers;

const config = {
  bifi: "0x639A647fbe20b6c8ac19E48E2de44ea792c62c5C",
  wNative: "0x471EcE3750Da237f93B8E339c536989b8978a438",
  treasury: "0xd9F2Da642FAA1307e4F70a5E3aC31b9bfe920eAF",
  rewardPool: "0x2D250016E3621CfC50A0ff7e5f6E34bbC6bfE50E",
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
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
