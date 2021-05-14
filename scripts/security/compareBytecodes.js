const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const trustedDeployments = {
  launchpool: "0x57db966945691Ac03C704566BF5E20207def4215",
};

const config = {
  target: "launchpool",
  contracts: ["0x57db966945691Ac03C704566BF5E20207def4215", "0xc1fcf50ccaCd1583BD9d3b41657056878C94e592"],
};

async function main() {
  const [signer] = await ethers.getSigners();

  let bytecodes = [];
  const trustedBytecode = await signer.provider.getCode(trustedDeployments[config.target]);
  for (const address of config.contracts) {
    const bytecode = await signer.provider.getCode(address);
    bytecodes.push(bytecode);
  }

  bytecodes.forEach((bytecode, i) => {
    if (bytecode !== trustedBytecode) {
      console.log(`Bytecode for contract ${config.contracts[i]} is different.`);
    }
  });
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
