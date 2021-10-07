import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "./tasks";

import { HardhatUserConfig } from "hardhat/src/types/config";
import { HardhatUserConfig as WithEtherscanConfig } from "hardhat/config";
import { buildHardhatNetworkAccounts, getPKs } from "./utils/configInit";

type DeploymentConfig = HardhatUserConfig & WithEtherscanConfig;

const accounts = getPKs();
const hardhatNetworkAccounts = buildHardhatNetworkAccounts(accounts);

const config: DeploymentConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      // accounts visible to hardhat network used by `hardhat node --fork` (yarn net <chainName>)
      accounts: hardhatNetworkAccounts,
    },
    bsc: {
      url: "https://bsc-dataseed2.defibit.io/",
      chainId: 56,
      accounts: accounts,
    },
    heco: {
      url: "https://http-mainnet-node.huobichain.com",
      chainId: 128,
      accounts: accounts,
    },
    avax: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: accounts,
    },
    polygon: {
      url: "https://polygon-rpc.com/",
      chainId: 137,
      accounts: accounts,
    },
    fantom: {
      url: "https://rpc.ftm.tools",
      chainId: 250,
      accounts: accounts,
    },
    one: {
      url: "https://api.s0.t.hmny.io/",
      chainId: 1666600000,
      accounts: accounts,
    },
    arbitrum: {
      url: "https://arb1.arbitrum.io/rpc",
      chainId: 42161,
      accounts: accounts,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 300000,
      accounts: "remote",
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      accounts: accounts,
    },
    kovan: {
      url: "https://kovan.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161",
      chainId: 42,
      accounts: accounts,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: "",
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
  },
};

export default config;
