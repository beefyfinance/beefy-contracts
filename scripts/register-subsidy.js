const hardhat = require("hardhat");
const ethers = hardhat.ethers;
const registerSubsidy = require("../utils/registerSubsidy");

const contracts = [
  // "0x847c5748A280d800690F7D3A62574603b57Cd0b7",
];

async function main() {
  const [deployer] = await ethers.getSigners();
  for (const address of contracts) {
    await registerSubsidy(address, deployer);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
