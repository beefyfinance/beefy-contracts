const { predictAddresses } = require("../utils/predictAddresses");

const deployVault = async (config) => {
  const predictedAddresses = await predictAddresses({ creator: config.signer.address, rpc: config.rpc });

  console.log(JSON.stringify(predictedAddresses));

  const Vault = await ethers.getContractFactory(config.vault);
  const vault = await Vault.deploy(
    config.want,
    predictedAddresses.strategy,
    config.mooName,
    config.mooSymbol,
    config.delay
  );
  await vault.deployed();

  const Strategy = await ethers.getContractFactory(config.strategy);
  const strategy = await Strategy.deploy(predictedAddresses.vault);
  await strategy.deployed();

  const _vault = await strategy.vault();
  const _strategy = await vault.strategy();

  console.log(vault.address, _vault);
  console.log(strategy.address, _strategy);

  return { vault, strategy };
};

module.exports = { deployVault };
