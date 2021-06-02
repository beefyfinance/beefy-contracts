import { task } from "hardhat/config";

task("node", "Starts a JSON-RPC server on top of Hardhat Network")
  .setAction(async (taskArgs, hre, runSuper) => {
    let network = hre.config.networks[taskArgs.fork];
    if (network && 'url' in network) {
      console.log(`Forking ${taskArgs.fork} from RPC: ${network.url}`);
      taskArgs.noReset = true;
      taskArgs.fork = network.url;
      if (network.chainId) {
        hre.config.networks.hardhat.chainId = network.chainId;
        hre.config.networks.localhost.chainId = network.chainId;
      }
    }
    await runSuper(taskArgs);
  });