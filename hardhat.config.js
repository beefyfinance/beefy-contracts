require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");

module.exports = {
  defaultNetwork: "localhost",
  networks: {
    hardhat: {},
    mainnet: {
      url: "https://bsc-dataseed.binance.org",
      chainId: 56,
      accounts: [process.env.HARDHAT_PK]
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 300000,
      accounts: "remote"
    }
  },
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: "./contracts/BIFI"
  },
  timeout: 30
};
