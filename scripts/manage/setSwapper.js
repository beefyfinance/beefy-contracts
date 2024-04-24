import { addressBook } from "blockchain-addressbook";
import { setOracle } from "./oracle/oracle";
import { setSwapper } from "./swapper/swapper";

const {
  tokens: {
    WETH: {address: WETH},
    AERO: {address: AERO},
    USDbC: {address: USDbC},
    USDC: {address: USDC},
    BASE: { address: BASE},
  },
} = addressBook.base;

const USDp = "0xB79DD08EA68A908A97220C76d19A6aA9cBDE4376";
const DAIp = "0x65a2508C429a6078a7BC2f7dF81aB575BD9D9275";

const swapper = "0x4e8ddA5727c62666Bc9Ac46a6113C7244AE9dbdf";
const oracle = "0x1BfA205114678c7d17b97DB7A71819D3E6718eb4";

const oracleParams = [
  {
    token: BASE,
    oracleType: 'uniswapV2',
    factory: "0x04C9f118d21e8B767D2e50C946f0cC9F6C367300",
    path: [WETH, BASE],
    twapPeriods: [300],
  },
  {
    token: WETH,
    oracleType: 'chainlink',
    feed: '0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70',
  },
  {
    token: USDC,
    oracleType: 'chainlink',
    feed: '0x7e860098F58bBFC8648a4311b374B1D669a2bc6B',
  },
  {
    token: USDp,
    oracleType: 'solidly',
    factory: "0x420DD381b31aEf6683db6B902084cB0FFECe40Da",
    path: [USDC, USDp],
    stable: [true],
    twapPeriods: [2], // 60 minutes
  },
  {
    token: DAIp,
    oracleType: 'solidly',
    factory: "0x420DD381b31aEf6683db6B902084cB0FFECe40Da",
    path: [USDp, DAIp],
    stable: [true],
    twapPeriods: [2], // 60 minutes
  }
];

const swapperParams = [
  {
    from: BASE,
    to: WETH,
    steps: [
      {
        stepType: 'uniswapV2',
        router: "0xaaa3b1F1bd7BCc97fD1917c18ADE665C5D31F066",
        path: [BASE, WETH],
      }
    ]
  },
  {
    from: BASE,
    to: USDbC,
    steps: [
      {
        stepType: 'uniswapV2',
        router: "0xaaa3b1F1bd7BCc97fD1917c18ADE665C5D31F066",
        path: [BASE, WETH],
      },
      {
        stepType: 'solidly',
        router: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
        path: [WETH, USDbC],
        stable: [false],
      }
    ]
  },
  {
    from: BASE,
    to: USDp,
    steps: [
      {
        stepType: 'uniswapV2',
        router: "0xaaa3b1F1bd7BCc97fD1917c18ADE665C5D31F066",
        path: [BASE, WETH],
      },
      {
        stepType: 'solidly',
        router: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
        path: [WETH, USDC, USDp],
        stable: [false, true],
      },
    ]
  },
  {
    from: BASE,
    to: DAIp,
    steps: [
      {
        stepType: 'uniswapV2',
        router: "0xaaa3b1F1bd7BCc97fD1917c18ADE665C5D31F066",
        path: [BASE, WETH],
      },
      {
        stepType: 'solidly',
        router: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
        path: [WETH, USDC, USDp, DAIp],
        stable: [false, true, true],
      }
    ]
  },
];

async function main() {
  await Promise.all([setOracle(oracle, oracleParams)]);
  await Promise.all([setSwapper(swapper, swapperParams)]);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });