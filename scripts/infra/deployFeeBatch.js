const hardhat = require("hardhat");
const { getImplementationAddress } = require("@openzeppelin/upgrades-core");

const ethers = hardhat.ethers;

const wnative = "0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83",
const bifi = "0xd6070ae98b8069de6B494332d1A1a81B6179D960",
const stable = "0x04068DA6C83AFCFA0e13ba15A6696662335D5B75",

const config = {
  treasury: "0xdFf234670038dEfB2115Cf103F86dA5fB7CfD2D2",
  rewardPool: "0x0000000000000000000000000000000000000000",
  unirouter: "0xF491e7B69E4244ad4002BC14e878a34207E38c29",
  bifi: bifi,
  wNative: wnative,
  stable: stable,
  bifiRoute: [wnative, bifi],
  stableRoute: [wnative, stable],
  splitTreasury: false,
  treasuryFee: 640
};

async function main() {
  await hardhat.run("compile");

  const deployer = await ethers.getSigner();
  const provider = deployer.provider;

  const BeefyFeeBatch = await ethers.getContractFactory("BeefyFeeBatchV3");

  const batcher = await upgrades.deployProxy(BeefyFeeBatch,  [
    config.bifi,
    config.wNative,
    config.stable,
    config.treasury,
    config.rewardPool,
    config.unirouter,
    config.bifiRoute, 
    config.stableRoute, 
    config.splitTreasury,
    config.treasuryFee
  ]
 );
  await batcher.deployed();

  const implementationAddr = await getImplementationAddress(provider, batcher.address);
  console.log("Deployed to:", batcher.address);
  console.log(`Deployed implementation at ${implementationAddr}`);

 
  console.log(`Verifing implementation`);
  await hardhat.run("verify:verify", {
    address: implementationAddr,
    constructorArguments: [
    ]
  })

}



main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
