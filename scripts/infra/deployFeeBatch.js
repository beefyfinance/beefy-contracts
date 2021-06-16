const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const config = {
  treasury: "0xe6CcE165Aa3e52B2cC55F17b1dBC6A8fe5D66610",
  rewardPool: "0x7fB900C14c9889A559C777D016a885995cE759Ee",
  unirouter: "0xF491e7B69E4244ad4002BC14e878a34207E38c29",
  bifi: "0xd6070ae98b8069de6b494332d1a1a81b6179d960",
  wNative: "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83",
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
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
