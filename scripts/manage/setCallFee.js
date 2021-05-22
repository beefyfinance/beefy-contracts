const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function setCallFee(uint256 _callFee) public", "function callFee() public view returns (uint256)"];
const newCallFee = 11;

const contracts = ["0x76BC10591eB5f2ED08Fd2C09B5aD1B01353D3C16"];

async function main() {
  for (const address of contracts) {
    const contract = await ethers.getContractAt(abi, address);
    const callFee = await contract.callFee();

    if (callFee.eq(newCallFee)) continue;

    let tx = await contract.setCallFee(newCallFee);
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
