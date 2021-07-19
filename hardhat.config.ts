require('dotenv').config()
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";

import { HardhatUserConfig } from "hardhat/src/types/config";
import { HardhatUserConfig as WithEtherscanConfig } from "hardhat/config";

type DeploymentConfig = HardhatUserConfig & WithEtherscanConfig;

const DEPLOYER_PK = [`${process.env.DEPLOYER_PK}`];
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY
const BSC_RPC = process.env.BSC_RPC
const HECO_RPC = process.env.HECO_RPC
const AVAX_RPC = process.env.AVAX_RPC
const POLYGON_RPC = process.env.POLYGON_RPC
const FANTOM_RPC = process.env.FANTOM_RPC
const LOCALHOST_RPC = process.env.LOCALHOST_RPC

const config: DeploymentConfig = {
  defaultNetwork: "localhost",
  networks: {
    hardhat: {},
    bsc: {
      url: BSC_RPC,
      chainId: 56,
      accounts: DEPLOYER_PK,
    },
    heco: {
      url: HECO_RPC,
      chainId: 128,
      accounts: DEPLOYER_PK,
    },
    avax: {
      url: AVAX_RPC,
      chainId: 43114,
      accounts: DEPLOYER_PK,
    },
    polygon: {
      url: POLYGON_RPC,
      chainId: 137,
      accounts: DEPLOYER_PK,
    },
    fantom: {
      url: FANTOM_RPC,
      chainId: 250,
      accounts: DEPLOYER_PK,
    },
    localhost: {
      url: LOCALHOST_RPC,
      timeout: 300000,
      accounts: "remote",
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      accounts: DEPLOYER_PK,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: ETHERSCAN_API_KEY,
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

export default config