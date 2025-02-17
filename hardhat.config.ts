import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@openzeppelin/hardhat-upgrades";
import "hardhat-gas-reporter";
import "hardhat-contract-sizer";
// import "@typechain/hardhat";
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
    mainnet: {
      url: process.env.MAINNET_RPC || "https://rpc.ankr.com/eth",
      chainId: 1,
      accounts,
    },
    ethereum: {
      url: process.env.ETH_RPC || "https://rpc.ankr.com/eth",
      chainId: 1,
      accounts,
    },
    bsc: {
      url: process.env.BSC_RPC || "https://rpc.ankr.com/bsc",
      chainId: 56,
      gasPrice: 1000000000,
      accounts,
    },
    heco: {
      url: process.env.HECO_RPC || "https://http-mainnet-node.huobichain.com",
      chainId: 128,
      accounts,
    },
    avax: {
      url: process.env.AVAX_RPC || "https://rpc.ankr.com/avalanche",
      chainId: 43114,
      accounts,
    },
    polygon: {
      url: process.env.POLYGON_RPC || "https://rpc.ankr.com/polygon",
      chainId: 137,
      gasPrice: 100000000000,
      accounts,
    },
    fantom: {
      url: process.env.FANTOM_RPC || "https://rpc.ankr.com/fantom",
      chainId: 250,
      accounts,
    },
    one: {
      url: process.env.ONE_RPC || "https://api.s0.t.hmny.io/",
      chainId: 1666600000,
      accounts,
    },
    arbitrum: {
      url: process.env.ARBITRUM_RPC || "https://arbitrum.rpc.subquery.network/public",
      chainId: 42161,
      accounts,
    },
    moonriver: {
      url: process.env.MOONRIVER_RPC || "https://rpc.moonriver.moonbeam.network",
      chainId: 1285,
      accounts,
    },
    celo: {
      url: process.env.CELO_RPC || "https://forno.celo.org",
      chainId: 42220,
      accounts,
    },
    cronos: {
      // url: "https://evm-cronos.crypto.org",
      url: process.env.CRONOS_RPC || "https://rpc.vvs.finance",
      chainId: 25,
      accounts,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      timeout: 300000,
      accounts: "remote",
    },
    testnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      chainId: 97,
      accounts,
    },
    kovan: {
      url: "https://kovan.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161",
      chainId: 42,
      accounts,
    },
    aurora: {
      url: process.env.AURORA_RPC || "https://mainnet.aurora.dev/Fon6fPMs5rCdJc4mxX4kiSK1vsKdzc3D8k6UF8aruek",
      chainId: 1313161554,
      accounts,
    },
    fuse: {
      url: process.env.FUSE_RPC || "https://rpc.fuse.io",
      chainId: 122,
      accounts,
    },
    metis: {
      url: process.env.METIS_RPC || "https://andromeda.metis.io/?owner=1088",
      chainId: 1088,
      accounts,
    },
    moonbeam: {
      url: process.env.MOONBEAM_RPC || "https://rpc.api.moonbeam.network",
      chainId: 1284,
      accounts,
    },
    sys: {
      url: process.env.SYS_RPC || "https://rpc.syscoin.org/",
      chainId: 57,
      accounts,
    },
    emerald: {
      url: process.env.EMERALD_RPC || "https://emerald.oasis.dev",
      chainId: 42262,
      accounts,
    },
    optimism: {
      url: process.env.OPTIMISM_RPC || "https://rpc.ankr.com/optimism",
      chainId: 10,
      accounts,
    },
    kava: {
      url: process.env.KAVA_RPC || "https://evm.kava.chainstacklabs.com",
      chainId: 2222,
      accounts,
    },
    canto: {
      url: process.env.CANTO_RPC || "https://canto.slingshot.finance",
      chainId: 7700,
      accounts,
    },
    zkevm: {
      url: process.env.ZKEVM_RPC || "https://zkevm-rpc.com",
      chainId: 1101,
      accounts,
    },
    base: {
      url: process.env.BASE_RPC || "https://mainnet.base.org",
      chainId: 8453,
      accounts,
    },
    linea: {
      url: process.env.LINEA_RPC || "https://rpc.linea.build",
      chainId: 59144,
      accounts,
    },
    mantle: {
      url: process.env.MANTLE_RPC || "https://rpc.mantle.xyz",
      chainId: 5000,
      accounts,
    },
    fraxtal: {
      url: process.env.FRAXTAL_RPC || "https://rpc.frax.com",
      chainId: 252,
      accounts,
      gasPrice: 100000,
    },
    mode: {
      url: process.env.MODE_RPC || "https://mainnet.mode.network",
      chainId: 34443,
      accounts,
    },
    real: {
      url: process.env.REAL_RPC || "https://real.drpc.org",
      chainId: 111188,
      accounts,
    },
    scroll: {
      url: process.env.SCROLL_RPC || "https://rpc.scroll.io",
      chainId: 534352,
      accounts,
    },
    rootstock: {
      url: "https://public-node.rsk.co",
      chainId: 30,
      accounts,
      gasPrice: 72000000,
    },
    manta: {
      url: process.env.MANTA_RPC || "https://manta-pacific.drpc.org",
      chainId: 169,
      accounts,
    },
    sei: {
      url: process.env.SEI_RPC || "https://evm-rpc.sei-apis.com",
      chainId: 1329,
      accounts,
    },
    lisk: {
      url: "https://rpc.api.lisk.com",
      chainId: 1135,
      accounts,
    },
    sonic: {
      url: process.env.SONIC_RPC || "https://rpc.ankr.com/sonic",
      chainId: 146,
      accounts,
    },
    unichain: {
      url: process.env.UNICHAIN_RPC || "https://mainnet.unichain.org",
      chainId: 130,
      accounts,
    },
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: {
      mainnet: process.env.MAINNET_API_KEY!,
      polygon: process.env.POLYGON_API_KEY!,
      zkevm: process.env.ZKEVM_API_KEY!,
      bsc: process.env.BSC_API_KEY!,
      optimisticEthereum: process.env.OPTIMISM_API_KEY!,
      base: process.env.BASE_API_KEY!,
      arbitrumOne: process.env.ARB_API_KEY!,
      opera: process.env.FANTOM_API_KEY!,
      linea: process.env.LINEA_API_KEY!,
      kava: "api key is not required by the Kava explorer, but can't be empty",
      metis: "api key is not required by the Kava explorer, but can't be empty",
      //snowtrace: "api key is not required by the Kava explorer, but can't be empty",
      mantle: process.env.MANTLE_API_KEY!,
      fraxtal: process.env.FRAXTAL_API_KEY!,
      mode: "api key is not required by the Kava explorer, but can't be empty",
      scroll: process.env.SCROLL_API_KEY!,
      rootstock: "abc",
      avax: process.env.AVAX_API_KEY!,
      manta: "someKey",
      sei: "sei",
      lisk: "abc",
      sonic: "abc",
      unichain: process.env.UNICHAIN_API_KEY!,
    },
    customChains: [
      {
        network: "scroll",
        chainId: 534352,
        urls: {
          apiURL: "https://api.scrollscan.com/api",
          browserURL: "https://scrollscan.com/",
        },
      },
      {
        network: "sonic",
        chainId: 146,
        urls: {
          apiURL: "https://api.sonicscan.org/api",
          browserURL: "https://sonicscan.org/",
        },
      },
      {
        network: "metis",
        chainId: 1088,
        urls: {
          apiURL: "https://andromeda-explorer.metis.io/api",
          browserURL: "https://andromeda-explorer.metis.io/",
        },
      },
      {
        network: "celo",
        chainId: 42220,
        urls: {
          apiURL: "https://api.celoscan.io/api/",
          browserURL: "https://celoscan.io/",
        },
      },
      {
        network: "zkevm",
        chainId: 1101,
        urls: {
          apiURL: "https://api-zkevm.polygonscan.com/api",
          browserURL: "https://zkevm.polygonscan.com/",
        },
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org/",
        },
      },
      {
        network: "kava",
        chainId: 2222,
        urls: {
          apiURL: "https://api.verify.mintscan.io/evm/api/0x8ae",
          browserURL: "https://kavascan.com/",
        },
      },
      {
        network: "avax",
        chainId: 43114,
        urls: {
          apiURL: "https://api.snowscan.xyz/api",
          browserURL: "https://avalanche.routescan.io",
        },
      },
      {
        network: "linea",
        chainId: 59144,
        urls: {
          apiURL: "https://api.lineascan.build/api",
          browserURL: "https://lineascan.build/",
        },
      },
      {
        network: "mantle",
        chainId: 5000,
        urls: {
          apiURL: "https://api.mantlescan.xyz/api",
          browserURL: "https://mantlescan.xyz/",
        },
      },
      {
        network: "fraxtal",
        chainId: 252,
        urls: {
          apiURL: "https://api.fraxscan.com/api",
          browserURL: "https://fraxscan.com/",
        },
      },
      {
        network: "mode",
        chainId: 34443,
        urls: {
          apiURL: "https://explorer.mode.network/api",
          browserURL: "https://modescan.io/",
        },
      },
      {
        network: "rootstock",
        chainId: 30,
        urls: {
          apiURL: "https://rootstock.blockscout.com/api",
          browserURL: "https://rootstock.blockscout.com/",
        },
      },
      {
        network: "manta",
        chainId: 169,
        urls: {
          apiURL: "https://pacific-explorer.manta.network/api",
          browserURL: "https://pacific-explorer.manta.network/",
        },
      },
      {
        network: "sei",
        chainId: 1329,
        urls: {
          apiURL: "https://seitrace.com/pacific-1/api",
          browserURL: "https://seitrace.com",
        },
      },
      {
        network: "lisk",
        chainId: 1135,
        urls: {
          apiURL: "https://blockscout.lisk.com/api",
          browserURL: "https://blockscout.lisk.com/",
        },
      },
      {
        network: "unichain",
        chainId: 130,
        urls: {
          apiURL: "https://api.uniscan.xyz/api",
          browserURL: "https://uniscan.xyz/",
        },
      },
    ],
  },
  solidity: {
    compilers: [
      {
        version: "0.8.23",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: "0.8.19",
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
