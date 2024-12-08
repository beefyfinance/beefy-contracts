const hardhat = require("hardhat");

const ethers = hardhat.ethers;

async function main() {
  await hardhat.run("compile");

  const Multicall = await ethers.getContractFactory("BeefyV2AppMulticall");

  const multicall = await Multicall.deploy();
  await multicall.deployed();

  console.log("App v2 multicall deployed:", multicall.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
