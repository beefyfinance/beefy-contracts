const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const swapper = "0x4e8ddA5727c62666Bc9Ac46a6113C7244AE9dbdf";
const swapBasedRouter = "0xaaa3b1F1bd7BCc97fD1917c18ADE665C5D31F066";

async function main() {
  await hardhat.run("compile");

  /*const [deployer] = await ethers.getSigners();

  const Strategy = await ethers.getContractFactory("SwapBasedUnirouter");
  const strategy = await Strategy.deploy(swapper, swapBasedRouter);
  await strategy.deployed();

  console.log("Candidate deployed to:", strategy.address);*/

  await hardhat.run("verify:verify", {
    address: "0x5DaE84c25E7E5a1259873730f7d2a528694A2095",
    constructorArguments: [swapper, swapBasedRouter],
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
