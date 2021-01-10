const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function transferOwnership(address newOwner) public"];
const newOwner = "0xd529b1894491a0a26B18939274ae8ede93E81dbA";

const contracts = [
  // "0x3c2C339d05d4911894F08Dd975e89630D7ef4234",
];

async function main() {
  for (const address of contracts) {
    const contract = await ethers.getContractAt(abi, address);
    const tx = await contract.transferOwnership(newOwner);
    await tx.wait();
    console.log(address, "done");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
