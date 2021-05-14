const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const contracts = ["0x57db966945691Ac03C704566BF5E20207def4215", "0xc1fcf50ccaCd1583BD9d3b41657056878C94e592"];

async function main() {
  const [signer] = await ethers.getSigners();

  let bytecodes = [];

  for (const address of contracts) {
    const bytecode = await signer.provider.getCode(address);
    bytecodes.push(bytecode);
  }

  bytecodes.forEach((bytecode, i) => {
    if (bytecode !== bytecodes[0]) {
      throw new Error(`Bytecode for contract ${contracts[i]} is different.`);
    }
  });

  console.log("All contracts are the same.");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
