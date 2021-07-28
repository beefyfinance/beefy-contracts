import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";

import { HardhatUserConfig } from "hardhat/src/types/config";
import { HardhatUserConfig as WithEtherscanConfig } from "hardhat/config";

type DeploymentConfig = HardhatUserConfig & WithEtherscanConfig;

let deployerAccount;
if (process.env.DEPLOYER_PK) deployerAccount = [process.env.DEPLOYER_PK];

const config: DeploymentConfig = {
  defaultNetwork: "localhost",
  networks: {
    hardhat: {},
    bsc: {
      url: "https://bsc-dataseed.binance.org/",
      chainId: 56,
      accounts: deployerAccount,
    },
    heco: {
      url: "https://http-mainnet-node.huobichain.com",
      chainId: 128,
      accounts: deployerAccount,
    },
    avax: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: deployerAccount,
    },
    polygon: {
      url: "https://rpc-mainnet.maticvigil.com/v1/de4204cef56aa2763bc505469cd11605e367e114",
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
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      accounts: deployerAccount,
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

export default config