import { task } from "hardhat/config";
import { HttpNetworkConfig } from "hardhat/types";
import { addressBook } from "blockchain-addressbook";

task("test-data:network-config", "Exports the current HardHat config to inject in forge tests").setAction(
  async (taskArgs: { data: "networks" | "addressbook" }, hre, runSuper) => {
    const cleanedNets: any = [];
    for (const netName in hre.config.networks) {
      let netConf = hre.config.networks[netName];
      if (netName === "hardhat") {
        // we can't use a net without url
        continue;
      } else if (netName === "localhost") {
        // we can't use a net without chain id
        continue;
      } else {
        netConf = netConf as HttpNetworkConfig;
        cleanedNets.push({
          name: netName,
          chaidId: netConf.chainId,
          url: netConf.url,
        });
      }
    }
    console.log(JSON.stringify(cleanedNets, null, 2));
  }
);

task("test-data:addressbook:beefy", "Fetch beefy addressbook to inject platform addresses in forge tests")
  .addParam("chain", "The chain name to fetch config from")
  .setAction(async (taskArgs: { chain: keyof typeof addressBook}, hre, runSuper) => {
    if (!(taskArgs.chain in addressBook)) {
      throw new Error(`Chain "${taskArgs.chain}" is not an address book chain. Chains: ${Object.keys(addressBook)}`);
    }
    const { beefyfinance } = addressBook[taskArgs.chain].platforms;
    const data = {
      keeper: beefyfinance.keeper,
      strategyOwner: beefyfinance.strategyOwner,
      vaultOwner: beefyfinance.vaultOwner,
    };
    console.log(JSON.stringify(data, null, 2));
  });
