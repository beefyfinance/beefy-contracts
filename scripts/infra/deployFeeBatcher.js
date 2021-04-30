const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  treasury: "0xA3e3Af161943CfB3941B631676134bb048739727",
  rewardPool: "0x86d38c6b6313c5A3021D68D1F57CF5e69197592A",
  unirouter: "0xE54Ca86531e17Ef3616d22Ca28b0D458b6C89106",
  bifi: "0xd6070ae98b8069de6B494332d1A1a81B6179D960",
  wNative: "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
};

async function main() {
  await hardhat.run("compile");

  const BeefyFeeBatch = await ethers.getContractFactory("BeefyFeeBatch");
  const batcher = await BeefyFeeBatch.deploy(
    config.treasury,
    config.rewardPool,
    config.unirouter,
    config.bifi,
    config.wNative
  );
  await batcher.deployed();

  console.log("Deployed to:", batcher.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
