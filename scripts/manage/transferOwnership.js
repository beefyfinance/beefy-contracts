const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook");

const { beefyfinance } = addressBook.bsc.platforms;

const ethers = hardhat.ethers;

const abi = ["function transferOwnership(address newOwner) public"];
const newOwner = "0xfcDD5a02C611ba6Fe2802f885281500EC95805d7"; //beefyfinance.devMultisig;
console.log("Transferring ownership to:", newOwner);

const contracts = ["0xdafF49F1bdBe7b1e3Bea83E2B4E0e40CE11E2e86"];

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
