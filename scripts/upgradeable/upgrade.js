const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");
const { addressBook } = require("blockchain-addressbook");

const { ethers, upgrades } = hardhat;

const chain = "fantom";
const a = addressBook[chain].platforms.beefyfinance.beefyFeeRecipient;

const config = {
  impl: "BeefyFeeBatchV2",
  proxy: "0x32C82EE8Fca98ce5114D2060c5715AEc714152FB",
};

async function main() {
  await hardhat.run("compile");

  const newImpl = await ethers.getContractFactory(config.impl);
  const upgraded = await upgrades.upgradeProxy(config.proxy, newImpl);

  console.log("Upgrade", upgraded.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
