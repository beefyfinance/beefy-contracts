const hardhat = require("hardhat");
const ethers = hardhat.ethers;

const pools = [
  {
    name: "Example Name",
    launchpool: "0x536F3d03130cB7FAf0821168e142b6c0Ea22ff86",
    amount: "1000000",
  },
];

async function main() {
  await hardhat.run("compile");

  for (pool of pools) {
    const baseUrl = "https://bscscan.com/tx/";

    const BeefyLaunchpadPool = await hardhat.artifacts.readArtifact("BeefyLaunchpadPool");
    const rewardsContract = await ethers.getContractAt(BeefyLaunchpadPool.abi, pool.launchpool);

    let tx = await rewardsContract.notifyRewardAmount(pool.amount);
    tx = await tx.wait();
    tx.status === 1
      ? console.log(`Pool ${pool.name} notified at: ${baseUrl}${tx.transactionHash}`)
      : console.log(`Could not notify ${pool.name} with tx at: ${baseUrl}${tx.transactionHash}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
