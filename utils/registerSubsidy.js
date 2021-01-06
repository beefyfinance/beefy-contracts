const ethers = require("ethers");
const IRewardRegister = require("../artifacts/contracts/BIFI/interfaces/binance/IRewardRegister.sol/IRewardRegister.json");

const registerSubsidy = async (vaultAddr, stratAddr, deployer) => {
  const subsidyHarvester = "0xd529b1894491a0a26B18939274ae8ede93E81dbA";
  const register = "0xCad9146102D29175Fd7908EB6820A48E4FC78CEA";
  const registerContract = new ethers.Contract(register, IRewardRegister.abi, deployer);

  let tx = await registerContract.registerContract(vaultAddr, subsidyHarvester);
  let url = `https://bscscan.com/tx/${tx.hash}`;
  console.log(`Vault registered for subsidy: ${url}`);

  tx = await registerContract.registerContract(stratAddr, subsidyHarvester);
  url = `https://bscscan.com/tx/${tx.hash}`;
  console.log(`Strategy registered for subsidy: ${url}`);
};

module.exports = registerSubsidy;
