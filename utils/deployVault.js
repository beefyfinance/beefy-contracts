const predictAddresses = require("../utils/predictAddresses");

const deployVault = async (config) => {
  const predictedAddresses = await predictAddresses({ creator: config.signer.address, rpc: config.rpc });

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
  const strategy = await Strategy.deploy(...config.stratArgs, predictedAddresses.vault);

  await strategy.deployed();

  return { vault, strategy };
};

module.exports = { deployVault };
