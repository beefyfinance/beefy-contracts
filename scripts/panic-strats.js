const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function panic() public"];

const contracts = [
  "0x50E33d0CB8664F9C2867c679d3C955A6b2A0faD4",
  "0x2D78a2Bbfa71c268beE36011F944901aF9b9d351",
  "0xcF662a5dB70B57D3616b5404801687f5ff657FBc",
  "0xd07308E588679C6F19682A83124F1F5022969EF2",
  "0x71D322ef2ad9b6b312Cc04A51a03C5f0Da74CaA0",
  "0x5D5d360c8529076800dfD9f57bCe514122Da35bB",
  "0x99bF8be49DcAc945a5754BDc0f5440Dc592D302a",
];

async function main() {
  for (const contract of contracts) {
    const strategy = await ethers.getContractAt(abi, contract);
    try {
      let tx = await strategy.panic({ gasLimit: 3500000, gasPrice: 5000000000 });
      tx = await tx.wait();
      tx.status === 1
        ? console.log(`Strat ${contract} panic() with tx: ${tx.transactionHash}`)
        : console.log(`Could not panic ${contract}} with tx: ${tx.transactionHash}`);
    } catch (err) {
      console.log(`Errr calling panic on ${contract} due to: ${err}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
