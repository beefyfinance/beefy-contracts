const ethers = require("ethers");
const IRewardRegister = require("../artifacts/contracts/BIFI/interfaces/binance/IRewardRegister.sol/IRewardRegister.json");

const registerSubsidy = async (contract, deployer) => {
  const register = "0xCad9146102D29175Fd7908EB6820A48E4FC78CEA";
  const registerContract = new ethers.Contract(register, IRewardRegister.abi, deployer);

  const tx = await registerContract.registerContract(contract, deployer.address);
  const url = `https://bscscan.com/tx/${tx.hash}`;
  console.log(`Contract registered for subsidy: ${url}`);
};

module.exports = registerSubsidy;
