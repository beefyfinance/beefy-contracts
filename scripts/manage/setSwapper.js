import { addressBook } from "blockchain-addressbook";
import { setOracle } from "./oracle/oracle";
import { setSwapper } from "./swapper/swapper";

const {
  tokens: {
    WETH: {address: WETH},
    AERO: {address: AERO},
  },
} = addressBook.base;

const swapper = "0x64b5C2b1E8a898dAa220a225cCB1788840c2e416";
const oracle = "0xA6aCCE42d739f4bf802499f2005a6ca4A10Fd611";

const oracleParams = [
  {
    token: AERO,
    oracleType: 'chainlink',
    feed: '0x4EC5970fC728C5f65ba413992CD5fF6FD70fcfF0',
  },
  {
    token: WETH,
    oracleType: 'chainlink',
    feed: '0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70',
  }
];

const swapperParams = [
  {
    from: AERO,
    to: WETH,
    steps: [
      {
        stepType: 'solidly',
        router: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
        path: [AERO, WETH],
        stable: [false],
        fees: [],
        poolId: [],
      }
    ]
  },
  {
    from: WETH,
    to: AERO,
    steps: [
      {
        stepType: 'solidly',
        router: "0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43",
        path: [WETH, AERO],
        stable: [false],
        fees: [],
        poolId: [],
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