import hardhat, { ethers, web3 } from "hardhat";
import BeefyOracleAbi from "../../data/abi/BeefyOracle.json";
import UniswapV3FactoryAbi from "../../data/abi/UniswapV3Factory.json";
import UniswapV2FactoryAbi from "../../data/abi/UniswapV2Factory.json";
import VelodromeFactoryAbi from "../../data/abi/VelodromeFactory.json";
import AerodromeFactory1Abi from "../../data/abi/AerodromeFactory1.json"
import AerodromeFactory2Abi from "../../data/abi/AerodromeFactory2.json"
import AerodromeFactory3Abi from "../../data/abi/AerodromeFactory2.json"
import { addressBook } from "blockchain-addressbook";

const {
  platforms: { beefyfinance },
  tokens: {
    USDC: { address: USDC},
    WETH: { address: ETH}
  },
} = addressBook.base;

const ethers = hardhat.ethers;

const nullAddress = "0x0000000000000000000000000000000000000000";
const uniswapV3Factory = "0xAAA32926fcE6bE95ea2c51cB4Fcb60836D320C42";
const uniswapV2Factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
const velodromeFactory = "0x92aF10c685D2CF4CD845388C5f45aC5dc97C5024";
const aerodromeFactory1 = "0x420DD381b31aEf6683db6B902084cB0FFECe40Da";
const aerodromeFactory2 = "0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A";
const aerodromeFactory3 = "0xade65c38cd4849adba595a4323a8c7ddfe89716a";

const beefyfinanceOracle = beefyfinance.beefyOracle;
const chainlinkOracle = beefyfinance.beefyOracleChainlink;
const uniswapV3Oracle = beefyfinance.beefyOracleUniswapV3;
const uniswapV2Oracle = beefyfinance.beefyOracleUniswapV2;
const solidlyOracle = beefyfinance.beefyOracleSolidly

const config = {
  type: "uniswapV2",
  chainlink: {
   // token: wstETH,
    feed: "0xe428fbdbd61CC1be6C273dC0E27a1F43124a86F3",
  },
  uniswapV3: {
 //   path: [[ETH, SCR, 3000]],
    twaps: [300],
    factory: uniswapV3Factory,
  },
  uniswapV2: {
    // path: [ETH, TOKE],
    twaps: [7200],
    factory: uniswapV2Factory,
  },
  solidly: {
  //  path: [[ETH, TKN, false]],
    twaps: [4],
    factory: velodromeFactory,
  },
  aerodromeCl: {
    path: [[ETH, oUSDT, 100]], // Insert token for pricing second and CL Pool Tick Spacing third
    twaps: [300],
    factory: aerodromeFactory2, // Check pool deployment tx events for correct factory contract address
  }
};

async function main() {
  switch(config.type) {
    case 'chainlink':
      await chainlink();
      break;
    case 'uniswapV3':
      await uniswapV3();
      break;
    case 'uniswapV2':
      await uniswapV2();
      break;
    case 'solidly':
      await solidly();
      break;
    case 'aerodromeCl':
      await aerodromeCl();
      break;
  }
};

async function chainlink() {
  const data = ethers.utils.defaultAbiCoder.encode(
    ["address"],
    [config.chainlink.feed]
  );

  await setOracle(config.chainlink.token, chainlinkOracle, data);
};

async function uniswapV3() {
  const factory = await ethers.getContractAt(UniswapV3FactoryAbi, config.uniswapV3.factory);
  const tokens = [];
  const pairs = [];
  for (let i = 0; i < config.uniswapV3.path.length; i++) {
    tokens.push(config.uniswapV3.path[i][0]);
    const pair = await factory.getPool(
      config.uniswapV3.path[i][0],
      config.uniswapV3.path[i][1],
      config.uniswapV3.path[i][2]
    );
    pairs.push(pair);
  }
  tokens.push(config.uniswapV3.path[config.uniswapV3.path.length - 1][1]);

  const data = ethers.utils.defaultAbiCoder.encode(
    ["address[]","address[]","uint256[]"],
    [tokens, pairs, config.uniswapV3.twaps]
  );

  await setOracle(tokens[tokens.length - 1], uniswapV3Oracle, data);
};

async function uniswapV2() {
  const factory = await ethers.getContractAt(UniswapV2FactoryAbi, config.uniswapV2.factory);
  const tokens = [];
  const pairs = [];
  for (let i = 0; i < config.uniswapV2.path.length - 1; i++) {
    tokens.push(config.uniswapV2.path[i]);
    const pair = await factory.getPair(
      config.uniswapV2.path[i],
      config.uniswapV2.path[i + 1]
    );
    pairs.push(pair);
  }
  tokens.push(config.uniswapV2.path[config.uniswapV2.path.length - 1]);

  console.log(tokens, pairs, config.uniswapV2.twaps)

  const data = ethers.utils.defaultAbiCoder.encode(
    ["address[]","address[]","uint256[]"],
    [tokens, pairs, config.uniswapV2.twaps]
  );

  await setOracle(tokens[tokens.length - 1], uniswapV2Oracle, data);
};

async function solidly() {
  const factory = await ethers.getContractAt(VelodromeFactoryAbi, config.solidly.factory);
  const tokens = [];
  const pairs = [];
  for (let i = 0; i < config.solidly.path.length; i++) {
    tokens.push(config.solidly.path[i][0]);
    const pair = await factory.getPair(
      config.solidly.path[i][0],
      config.solidly.path[i][1],
      config.solidly.path[i][2]
    );
    pairs.push(pair);
  }
  tokens.push(config.solidly.path[config.solidly.path.length - 1][1]);

  const data = ethers.utils.defaultAbiCoder.encode(
    ["address[]","address[]","uint256[]"],
    [tokens, pairs, config.solidly.twaps]
  );

  await setOracle(tokens[tokens.length - 1], solidlyOracle, data);
};

async function aerodromeCl() {
  const factory = await ethers.getContractAt(AerodromeFactory2Abi, config.aerodromeCl.factory);
  const tokens = [];
  const pairs = [];
  for (let i = 0; i < config.aerodromeCl.path.length; i++) {
    tokens.push(config.aerodromeCl.path[i][0]);
    const pair = await factory["getPool(address,address,int24)"]( // Note: Aero uses getPool, not getPair
      config.aerodromeCl.path[i][0],
      config.aerodromeCl.path[i][1],
      config.aerodromeCl.path[i][2]
    );
    pairs.push(pair);
  }

  tokens.push(config.aerodromeCl.path[config.aerodromeCl.path.length - 1][1]);

  const data = ethers.utils.defaultAbiCoder.encode(
    ["address[]","address[]","uint256[]"],
    [tokens, pairs, config.aerodromeCl.twaps]
  );

  // console.log(tokens[tokens.length - 1], uniswapV3Oracle, data); // For use by those without keeper access. Submit logs to those with keeper access.

  await setOracle(tokens[tokens.length - 1], uniswapV3Oracle, data); // For use by those with keeper access.
}

async function setOracle(token, oracle, data) {
  const [_, keeper, __] = await ethers.getSigners();
  const oracleContract = await ethers.getContractAt(BeefyOracleAbi, beefyfinanceOracle, keeper);

  let tx = await oracleContract.setOracle(token, oracle, data);
  tx = await tx.wait();
    tx.status === 1
      ? console.log(`Info set for ${token} with tx: ${tx.transactionHash}`)
      : console.log(`Could not set info for ${token}} with tx: ${tx.transactionHash}`)
};

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
