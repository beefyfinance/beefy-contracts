const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function panic() public"];

const contracts = [
  "0x798552Be40E2aF875F771a5A200975E3Db544FF4",
  "0x00e0EA0fd65917D723EA930a16d3CBb94Fe3E2eF",
  "0xfE9737A98f7a8fAA465A442c9fe5473328d2725f",
  "0xCDE1BecE18756EE67e32D877326187871055dA6E",
  "0x857b119e2494f8b4E06dd23BcbaB4aF4F1820dEa",
  "0xfF51E64c17939F6aDf6Ad3da2d2fC440Ac7Cdc3f",
  "0xB5968312cEBED11E5DDF7b3b56c28Ae084d290C7",
  "0x4fB6fA862081796fe22f9D527A27dE6e2779Be59",
  "0x8329ef7D376389F20F4f8CB8279f5D02dcC3CB23",
  "0x87f86C9D9676A77aCC068528AB934B5CbBFe9479",
  "0x82FCd3c30E8353e432c5F2Da10eE586015717B00",
  "0xc898F4ee9F3194d6Ed8B8D0E567100cE8038Eb57",
  "0xe79fF4C4E1D78a483C63583330dCC7319f05aFDf",
  "0x19A246CE9698eEEf9a6C851C034f6f3E71E4902f",
  "0x14FCa2E3337eB956d9c810652216EFe147E0CEF8",
  "0x70aEf5d199fDfaAC5A81747C8b7C91F77f2B6F54",
  "0xb506bEF03ec669f122c0F276e3848239aB829Dbb",
  "0x7b8056527faF16FF0BF2742A79Fe3b1C9A27fD7e",
  "0x0042Fb96b4Ef358b65F8d11c8D7d703C41c2d1b3",
  "0x9204F0d9aC07c839fbCb0c22c326ccef51A8Aba4",
  "0x7f4deaca74a6aBbc573FB8FDf244D6d0e4c07976",
  "0x21428EABd16a2610f6b7221B0FE2Ab7Eb903088a",
  "0x6A164e8DF6F554Cb2C9F4CF9a407E799b60fF497",
  "0x5C3847e558a82af69ab2aCe7A8eCe39E3d81A861",
];

async function main() {
  for (const contract of contracts) {
    const strategy = await ethers.getContractAt(abi, contract);
    try {
      const tx = await strategy.panic({ gasLimit: 3500000, gasPrice: 10000000000 });
      const url = `https://bscscan.com/tx/${tx.hash}`;
      console.log(`Successful panic at ${url}`);
    } catch (err) {
      console.log(`Could not panic due to: ${err}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
