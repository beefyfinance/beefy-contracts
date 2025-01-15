const hardhat = require("hardhat");

const ethers = hardhat.ethers;

async function main() {
  await hardhat.run("compile");

  const MulticallV2 = await ethers.getContractFactory("BeefyV2AppMulticall");
  const Multicall = await ethers.getContractFactory("Multicall");

  const multicallV2 = await MulticallV2.deploy();
  const multicall = await Multicall.deploy();

  await multicallV2.deployed();
  await multicall.deployed();

  console.log("Multicall deployed:", multicall.address);
  console.log("App v2 multicall deployed:", multicallV2.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
