import { addressBook } from "blockchain-addressbook";
import hardhat from "hardhat";

const ethers = hardhat.ethers;

const abi = ["function transferOwnership(address newOwner) public"];
const newOwner = addressBook.polygon.platforms.beefyfinance.strategyOwner;

const contracts = ["0x46FfF3f004afeE180CF96cCa92560a94A696044B"];

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
