const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function setBeefyFeeRecipient(address _beefyFeeRecipient) public"];
const newRecipient = "0x425Ee7d8dc6Ee14878D8F2D2b44d896858F4A818";

const contracts = ["0xbE5370a50d11D10475089222497A4172bdC600a4"];

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
