const hardhat = require("hardhat");
const ethers = hardhat.ethers;

const pools = [
  {
    name: "NUTS",
    launchpool: "0x02e2B4212b8F5610E2ab548cB680cb58E61056F6",
    amount: "19000000000000000000000",
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
