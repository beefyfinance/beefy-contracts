const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function transferOwnership(address newOwner) public"];
const newOwner = "0x362704FC0e43Ad29963331AC986645ff6b0e8552";

const contracts = ["0x1BA1B43227325E8Dc0FA1378d7C41fa7F49e32e0"];

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
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
