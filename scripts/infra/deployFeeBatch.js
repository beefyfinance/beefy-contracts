const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");

const ethers = hardhat.ethers;

const config = {
  treasury: "0x4A32De8c248533C28904b24B4cFCFE18E9F2ad01",
  rewardPool: "0x0d5761D9181C7745855FC985f646a842EB254eB9",
  unirouter: "0x10ED43C718714eb63d5aA57B78B54704E256024E",
  bifi: "0xCa3F508B8e4Dd382eE878A314789373D80A5190A",
  wNative: "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
};



async function main() {
  await hardhat.run("compile");

  const deployer = await ethers.getSigner();
  const provider = deployer.provider;

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
  console.log("Deployed to:", batcher.address);
  console.log(`Deployed implementation at ${implementationAddr}`);

}



main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
