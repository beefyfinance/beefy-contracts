import hardhat, { ethers, web3 } from "hardhat";
import BeefyOracleAbi from "../../data/abi/BeefyOracle.json";
import UniswapV3FactoryAbi from "../../data/abi/UniswapV3Factory.json";
import UniswapV2FactoryAbi from "../../data/abi/UniswapV2Factory.json";
import VelodromeFactoryAbi from "../../data/abi/VelodromeFactory.json";
import { addressBook } from "blockchain-addressbook";

const {
  platforms: { beefyfinance },
  tokens: {
    WMATIC: {address: WMATIC},
    USDC: { address: USDC},
    ETH: { address: ETH},
  },
} = addressBook.polygon;

const ethers = hardhat.ethers;

const nullAddress = "0x0000000000000000000000000000000000000000";
const uniswapV3Factory = "0x1F98431c8aD98523631AE4a59f267346ea31F984";
const uniswapV2Factory = "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f";
const velodromeFactory = "0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a";

const beefyfinanceOracle = "0x70655508b04cCB34781e557Ad4605D3fe0d98D79";
const chainlinkOracle = "0xf89703fc237DFAaA28b3d1D4835c7540cd2D0885";
const uniswapV3Oracle = "0x0000000000000000000000000000000000000000";
const uniswapV2Oracle = "0x0000000000000000000000000000000000000000";
const solidlyOracle = "0x0000000000000000000000000000000000000000";

const config = {
  type: "chainlink",
  chainlink: {
    token: ETH,
    feed: "0xF9680D99D6C9589e2a93a78A04A279e509205945",
  },
  uniswapV3: {
    path: [[USDC, WMATIC, 500]],
    twaps: [7200],
    factory: uniswapV3Factory,
  },
  uniswapV2: {
    path: [USDC, WMATIC],
    twaps: [7200],
    factory: uniswapV2Factory,
  },
  solidly: {
    path: [[USDC, WMATIC, false]],
    twaps: [4],
    factory: velodromeFactory,
  },
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
    [tokens, pairs, config.uniswapV3.twapPeriods]
  );

  await setOracle(tokens[tokens.length - 1], uniswapV3Oracle, data);
};

async function uniswapV2() {
  const factory = await ethers.getContractAt(UniswapV2FactoryAbi, config.uniswapV2.factory);
  const tokens = [];
  const pairs = [];
  for (let i = 0; i < config.uniswapV2.path.length - 1; i++) {
    tokens.push(config.uniswapV2.path[i][0]);
    const pair = await factory.getPair(
      config.uniswapV2.path[i],
      config.uniswapV2.path[i + 1]
    );
    pairs.push(pair);
  }
  tokens.push(config.uniswapV2.path[config.uniswapV2.path.length - 1]);

  const data = ethers.utils.defaultAbiCoder.encode(
    ["address[]","address[]","uint256[]"],
    [tokens, pairs, config.uniswapV2.twapPeriods]
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
    [tokens, pairs, config.solidly.twapPeriods]
  );

  await setOracle(tokens[tokens.length - 1], solidlyOracle, data);
};

async function setOracle(token, oracle, data) {
  const oracleContract = await ethers.getContractAt(BeefyOracleAbi, beefyfinanceOracle);

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
