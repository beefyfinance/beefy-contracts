const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function setBeefyFeeRecipient(address _beefyFeeRecipient) public"];
const newRecipient = "0x86d38c6b6313c5A3021D68D1F57CF5e69197592A";

const contracts = ["0xbE5370a50d11D10475089222497A4172bdC600a4", "0x3B289DcCd55B46596FbBAFfEd6469a85d69426Dc"];

async function main() {
  for (const address of contracts) {
    const contract = await ethers.getContractAt(abi, address);
    let tx = await contract.setBeefyFeeRecipient(newRecipient);
    tx = await tx.wait();
    tx.status === 1
      ? console.log(`${address} done with tx: ${tx.transactionHash}`)
      : console.log(`${address} failed with tx: ${tx.transactionHash}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
