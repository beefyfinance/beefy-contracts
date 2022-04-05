const hardhat = require("hardhat");
const { addressBook } = require("blockchain-addressbook");

const { beefyfinance } = addressBook.bsc.platforms;

const ethers = hardhat.ethers;

const abi = ["function transferOwnership(address newOwner) public"];
//const newOwner = "0xfcDD5a02C611ba6Fe2802f885281500EC95805d7"; // strategyOwner
const newOwner = "0xc8F3D9994bb1670F5f3d78eBaBC35FA8FdEEf8a2"; // vaultOwner
//beefyfinance.devMultisig;
console.log("Transferring ownership to:", newOwner);

const contracts = ["0x35aACc4c63ac4e3459d67964014E158d5132a25e"];

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
