const ethers = require("ethers");

const BeefyLaunchpadPool = require("../artifacts/contracts/BIFI/launchpad/BeefyLaunchpadPool.sol/BeefyLaunchpadPool.json");

const config = {
  launchpool: "",
  amount: "",
};

const rewards = "0x453D4Ba9a2D594314DF88564248497F7D74d6b2C";

const notifyRewards = async () => {
  const provider = new ethers.providers.JsonRpcProvider(process.env.BSC_RPC);
  const harvester = new ethers.Wallet(process.env.REWARDER_PRIVATE_KEY, provider);
  const rewardsContract = new ethers.Contract(config.launchpool, BeefyLaunchpadPool, harvester);

  await rewardsContract.notifyRewardAmount(config.amount);
};

module.exports = notifyRewards;
