const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function panic() public", "function paused() public view returns (bool)"];

const contracts = [
  "0xb16ceE470632ba94b7d21d2bC56d284ff0b0C04C",
  "0xBF36AF3bfE6C4cD0286C24761060488eB1af2618",
  "0xf8B5Cb47232938f1A75546fA5182b8af312Fc380",
  "0xfA416c3b89cc2E7902F58A4bEA62Ab7E24bd5985",
  "0x45973436B06e46dc37333e65f98A190A392476a4",
  "0xB126E22F4d9EfE943c94E0Ef493FF34f98AdC9E1",
];

async function main() {
  const [_, keeper, rewarder] = await ethers.getSigners();

  for (const contract of contracts) {
    const strategy = await ethers.getContractAt(abi, contract, rewarder);
    try {
      const paused = await strategy.paused();

      if (!paused) {
        let tx = await strategy.panic({ gasLimit: 3500000 });
        tx = await tx.wait();
        tx.status === 1
          ? console.log(`Strat ${contract} panic() with tx: ${tx.transactionHash}`)
          : console.log(`Could not panic ${contract}} with tx: ${tx.transactionHash}`);
      }
    } catch (err) {
      console.log(`Errr calling panic on ${contract} due to: ${err}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
