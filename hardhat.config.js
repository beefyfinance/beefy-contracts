require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-web3");
require("@nomiclabs/hardhat-ethers");

task("panic", "Panics a given strategy.")
  .addParam("strat", "The strategy to panic.")
  .setAction(async taskArgs => {
    const IStrategy = await hre.artifacts.readArtifact("IStrategy");
    const strategy = await ethers.getContractAt(IStrategy.abi, taskArgs.strat);

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
  .setAction(async taskArgs => {
    const IStrategy = await hre.artifacts.readArtifact("IStrategy");
    const strategy = await ethers.getContractAt(IStrategy.abi, taskArgs.strat);

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
  .setAction(async taskArgs => {
    const IStrategy = await hre.artifacts.readArtifact("IStrategy");
    const strategy = await ethers.getContractAt(IStrategy.abi, taskArgs.strat);

    try {
      const tx = await strategy.harvest({ gasPrice: 10000000000, gasLimit: 3500000 });
      const url = `https://bscscan.com/tx/${tx.hash}`;
      console.log(`Successful harvest with tx at ${url}`);
    } catch (err) {
      console.log(`Couldn't harvest due to ${err}`);
    }
  });

module.exports = {
  defaultNetwork: "localhost",
  networks: {
    hardhat: {},
    bsc: {
      url: "https://bsc-dataseed1.ninicoin.io/",
      chainId: 56,
      accounts: [process.env.DEPLOYER_PK],
    },
    heco: {
      url: "https://http-mainnet.hecochain.com",
      chainId: 128,
      accounts: [process.env.DEPLOYER_PK],
    },
    avax: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: [process.env.DEPLOYER_PK],
    },
    polygon: {
      url: "https://rpc-mainnet.maticvigil.com/",
      chainId: 137,
      accounts: [process.env.DEPLOYER_PK],
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 300000,
      accounts: "remote",
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      accounts: [process.env.DEPLOYER_PK],
    },
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
  timeout: 30,
};
