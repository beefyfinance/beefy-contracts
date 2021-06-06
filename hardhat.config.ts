import fs from "fs";

import { task, HardhatUserConfig } from "hardhat/config";
import { HttpNetworkConfig } from 'hardhat/types';

import 'hardhat-deploy';
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-ethers";

import { addressBook } from "blockchain-addressbook";

const DEPLOYER_PK_FILE = ".config/DEPLOYER_PK";
const OTHER_PK_FILE = ".config/OTHER_PK";

task("node", "Starts a JSON-RPC server on top of Hardhat Network")
  .setAction(async (taskArgs, hre, runSuper) => {
    let network = hre.config.networks[taskArgs.fork] as HttpNetworkConfig;
    if (network) {
      let rpc = network.url;
      console.log(`Forking ${taskArgs.fork} from RPC: ${rpc}`);
      taskArgs.fork = rpc;
    }
    await runSuper(taskArgs);
  });

task("panic", "Panics a given strategy.")
  .addParam("strat", "The strategy to panic.")
  .setAction(async (taskArgs, hre) => {
    const IStrategy = await hre.artifacts.readArtifact("IStrategy");
    const strategy = await hre.ethers.getContractAt(IStrategy.abi, taskArgs.strat);

    try {
      const tx = await strategy.panic({ gasPrice: 10000000000, gasLimit: 3500000 });
      const url = `https://bscscan.com/tx/${tx.hash}`;
      console.log(`Successful panic with tx at ${url}`);
    } catch (err) {
      console.log(`Couldn't panic due to ${err}`);
    }
  });

task("unpause", "Unpauses a given strategy.")
  .addParam("strat", "The strategy to unpause.")
  .setAction(async (taskArgs, hre) => {
    const IStrategy = await hre.artifacts.readArtifact("IStrategy");
    const strategy = await hre.ethers.getContractAt(IStrategy.abi, taskArgs.strat);

    try {
      const tx = await strategy.unpause({ gasPrice: 10000000000, gasLimit: 3500000 });
      const url = `https://bscscan.com/tx/${tx.hash}`;
      console.log(`Successful unpaused with tx at ${url}`);
    } catch (err) {
      console.log(`Couldn't unpause due to ${err}`);
    }
  });

task("harvest", "Harvests a given strategy.")
  .addParam("strat", "The strategy to harvest.")
  .setAction(async (taskArgs, hre) => {
    const IStrategy = await hre.artifacts.readArtifact("IStrategy");
    const strategy = await hre.ethers.getContractAt(IStrategy.abi, taskArgs.strat);

    try {
      const tx = await strategy.harvest({ gasPrice: 10000000000, gasLimit: 3500000 });
      const url = `https://bscscan.com/tx/${tx.hash}`;
      console.log(`Successful harvest with tx at ${url}`);
    } catch (err) {
      console.log(`Couldn't harvest due to ${err}`);
    }
  });

task("generate_accounts", "Creates new deployer and test accounts")
  .setAction(async (taskArgs, hre) => {
    let account;
    let file;

    try {
      fs.mkdirSync(".config");
    }
    catch (e) { }

    try {
      file = fs.openSync(DEPLOYER_PK_FILE, 'wx+', 0o600);
      account = hre.ethers.Wallet.createRandom();
      fs.writeFileSync(file, account.privateKey);
      console.log(`Deployer account: ${account.address}`);
    }
    catch (e) {
      if (e.code === 'EEXIST') {
        console.log("Deployer key exists. Not overwriting");
      }
      else {
        console.error(e);
      }
    }
    finally {
      if (file) {
        fs.closeSync(file);
        file = null;
      }
    }

    try {
      file = fs.openSync(OTHER_PK_FILE, 'wx+', 0o600);
      account = hre.ethers.Wallet.createRandom();
      fs.writeFileSync(file, account.privateKey);
      console.log(`Other account  : ${account.address}`);
    }
    catch (e) {
      if (e.code === 'EEXIST') {
        console.log("Other key exists. Not overwriting");
      }
      else {
        console.error(e);
      }
    }
    finally {
      if (file) {
        fs.closeSync(file);
        file = null;
      }
    }
  });

let deployerAccount;
if (process.env.DEPLOYER_PK)
  deployerAccount = [process.env.DEPLOYER_PK];
else {
  try {
    deployerAccount = [fs.readFileSync(DEPLOYER_PK_FILE).toString()];
  }
  catch (e) {
    if (e.code === 'ENOENT') {
      console.log("Deployer account not found. Create .config/DEPLOYER_PK or run `hardhat generate_accounts`.");
    }
    else {
      console.error(e);
    }
  }
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      loggingEnabled: true,
      tags: ['dev']
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      accounts: deployerAccount,
    },
    heco: {
      url: "https://http-mainnet.hecochain.com",
      chainId: 128,
      accounts: deployerAccount,
    },
    avax: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: deployerAccount,
    },
    polygon: {
      url: "https://rpc-mainnet.maticvigil.com/",
      chainId: 137,
      accounts: deployerAccount,
    },
    fantom: {
      url: "https://rpc.ftm.tools",
      chainId: 250,
      accounts: deployerAccount,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 300000,
      accounts: "remote",
      tags: ['dev']
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      accounts: deployerAccount,
    },
  },
  namedAccounts: {
    deployer: {
      default: 0
    },
    user: {
      default: 1
    },
    keeper: {
      default: 0,
      bsc: addressBook.bsc.platforms.beefyfinance.keeper,
      polygon: addressBook.polygon.platforms.beefyfinance.keeper,
      fantom: addressBook.fantom.platforms.beefyfinance.keeper,
      avax: addressBook.avax.platforms.beefyfinance.keeper,
      heco: addressBook.heco.platforms.beefyfinance.keeper
    },
    owner: {
      default: 0,
      bsc: addressBook.bsc.platforms.beefyfinance.vaultOwner,
      polygon: addressBook.polygon.platforms.beefyfinance.vaultOwner,
      fantom: addressBook.fantom.platforms.beefyfinance.vaultOwner,
      avax: addressBook.avax.platforms.beefyfinance.vaultOwner,
      heco: addressBook.heco.platforms.beefyfinance.vaultOwner
    }
  },
  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.5.5",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  paths: {
    sources: "./contracts/BIFI",
  }
};
export default config;