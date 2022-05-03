const hardhat = require("hardhat");
import { addressBook } from "blockchain-addressbook";
const {
    platforms: { pancake, beefyfinance },
    tokens: {
      BNB: { address: BNB },
      CAKE: { address: CAKE },
    },
  } = addressBook.bsc;
  

const ethers = hardhat.ethers;

async function main() {
    await hardhat.run("compile");

    const RewardPool = await ethers.getContractFactory("BeefyRewardPool");

    const Batch = await ethers.getContractFactory("BeTokenBatch");

    const beToken = web3.utils.toChecksumAddress("0x42b50A901228fb4C739C19fcd38DC2182B515B66");
    const config = {
        stakedToken: beToken,
        rewardToken: CAKE,
        unirouter: pancake.router,
        feeBatch: beefyfinance.beefyFeeRecipient,
        route: [CAKE, BNB],
    };

    console.log("Deploying Reward Pool...")
    const rewardPool = await RewardPool.deploy(config.stakedToken, config.rewardToken);
    await rewardPool.deployed();

    console.log(`RewardPool deployed ${rewardPool.address}`);

    console.log("Deploying BeToken FeeBatch...")
    const batch = await Batch.deploy(rewardPool.address, config.unirouter, config.feeBatch, config.route);
    await batch.deployed();

    console.log(`BeToken Batch deployed to ${batch.address}`);

    console.log("Transfering Ownership of RewardPool to FeeBatch");
    let tx = await rewardPool.transferOwnership(batch.address);
    tx = await tx.wait();
    console.log(`Ownership Transfered succesfully ${tx.transactionHash}`);

    await hardhat.run("verify:verify", {
        address: batch.address,
        constructorArguments: [
          rewardPool.address,
          config.unirouter,
          config.feeBatch,
          config.route,
        ],
      })
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
