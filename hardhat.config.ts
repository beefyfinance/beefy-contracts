import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "hardhat-deploy";
import './tasks';

import { HardhatUserConfig } from "hardhat/config";
import { addressBook } from "../address-book/build/address-book";

const accounts = (()=>{
  if (process.env.DEPLOYER_PK !== undefined) {
    const accounts = [process.env.DEPLOYER_PK];
    if (process.env.KEEPER_PK) accounts.push(process.env.KEEPER_PK);
    if (process.env.UPGRADER_PK) accounts.push(process.env.UPGRADER_PK);
    return accounts;
  }
  else {
    return undefined;
  }
})();

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {},
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
    }
  },
  namedAccounts: {
    deployer: 0,
    keeper: {
      default: 1,
      bsc    : addressBook.bsc    .platforms.beefyfinance.keeper,
      heco   : addressBook.heco   .platforms.beefyfinance.keeper,
      avax   : addressBook.avax   .platforms.beefyfinance.keeper,
      polygon: addressBook.polygon.platforms.beefyfinance.keeper,
      fantom : addressBook.fantom .platforms.beefyfinance.keeper,
    },
    vaultOwner: {
      default: 2,
      bsc    : addressBook.bsc    .platforms.beefyfinance.vaultOwner,
      heco   : addressBook.heco   .platforms.beefyfinance.vaultOwner,
      avax   : addressBook.avax   .platforms.beefyfinance.vaultOwner,
      polygon: addressBook.polygon.platforms.beefyfinance.vaultOwner,
      fantom : addressBook.fantom .platforms.beefyfinance.vaultOwner,
    }
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