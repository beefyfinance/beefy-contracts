import { ethers } from "ethers";
import { task } from "hardhat/config";
import { HttpNetworkConfig } from "hardhat/types";
import { addressBook, addressBookByChainId } from "blockchain-addressbook";
import Chain from "blockchain-addressbook/build/types/chain";

task("test-data:network-config", "Exports the current HardHat config to inject in forge tests").setAction(
  async (taskArgs: { data: "networks" | "addressbook" }, hre, runSuper) => {
    const cleanedNets: any = [];
    for (const netName in hre.config.networks) {
      let netConf = hre.config.networks[netName];
      if (netName === "hardhat") {
        // we can't use a net without url
        continue;
      } else {
        netConf = netConf as HttpNetworkConfig;
        cleanedNets.push({
          name: netName,
          chaidId: netConf.chainId || -1,
          url: netConf.url,
        });
      }
    }
    console.log(JSON.stringify(cleanedNets, null, 2));
  }
);

task("test-data:addressbook:beefy", "Fetch beefy addressbook to inject platform addresses in forge tests")
  .addParam("chain", "The chain name to fetch config from")
  .setAction(async (taskArgs: { chain: keyof typeof addressBook & "localhost"}, hre, runSuper) => {
    if (!(taskArgs.chain in addressBook) && taskArgs.chain !== "localhost") {
      throw new Error(`Chain "${taskArgs.chain}" is not an address book chain. Chains: ${Object.keys(addressBook)}`);
    }

    let chainConfig: Chain;
    if (taskArgs.chain === "localhost") {
      const netConf = hre.config.networks.localhost as HttpNetworkConfig;
      const provider = new ethers.providers.JsonRpcProvider(netConf.url);
      const chainId = await provider.getNetwork().then(n => n.chainId);
      chainConfig = addressBookByChainId[(chainId + "") as keyof typeof addressBookByChainId];
    } else {
      chainConfig = addressBook[taskArgs.chain];
    }
    const { beefyfinance } = chainConfig.platforms;
    const data = {
      keeper: beefyfinance.keeper,
      strategyOwner: beefyfinance.strategyOwner,
      vaultOwner: beefyfinance.vaultOwner,
    };
    console.log(JSON.stringify(data, null, 2));
  });
