const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function upgradeStrat() public"];

const addresses = [
  "0x7a670e849DB824364d1031DEAfB4cD603144F23D",
  "0xDA875A511860f2752B891677489d08CaEDac00EA",
  "0xd5ab3Fac6200B0D8e8d76daED62793026118A78c",
  "0x6571052b2FB67DF6DD003ED6ed371098A030Eb0d",
  "0x17657955D954bD7F7315C388D7099af7B0b851FA",
  "0x044e87f30bd9bD961c04028aC69155493E1b9eD0",
];

async function main() {
  for (const address of addresses) {
    const vault = await ethers.getContractAt(abi, address);
    try {
      let tx = await await vault.upgradeStrat();
      tx = await tx.wait();
      tx.status === 1
        ? console.log(`Vault ${address} upgraded with tx: ${tx.transactionHash}`)
        : console.log(`Could not upgrade ${address}} with tx: ${tx.transactionHash}`);
    } catch (err) {
      console.log(`Error upgrading vault ${address}: ${err}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
