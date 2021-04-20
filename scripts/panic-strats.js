const hardhat = require("hardhat");

const ethers = hardhat.ethers;

const abi = ["function panic() public"];

const contracts = [
  "0xCA26A1f9d3e6Ec97a555d9444f782d61b64C1B0e",
  "0x0a350c62f4b8C7dA93fBca469e53a182b5BBD044",
  "0x3c2C339d05d4911894F08Dd975e89630D7ef4234",
  "0x70C247ac8323B9ca340857d2893F4aa4F7E16D5f",
  "0xBB0C9d495F555E754ACDb76Ed127a9C115132206",
  "0x131fE92ff0288915883d6c122Cb76D68c5145D87",
  "0xfa3ccb086bf371a2ff33db8521be47c5b4b9d10e",
  "0x8c1244aCCD534025641CFF00D4ee5616FcbeE154",
  "0xe865Ba185895634D094767688aC1c69751cb06aa",
  "0x45640eE6e2BE2bA6752909f2e57C32C4997965d2",
  "0x77ed2908e3cE2197882993DF9432E69079b146B6",
  "0x76788df486C07750Ce915D88093872470e5e3E45",
];

async function main() {
  for (const contract of contracts) {
    const strategy = await ethers.getContractAt(abi, contract);
    try {
      const tx = await strategy.panic({ gasLimit: 3500000, gasPrice: 5000000000 });
      const url = `https://bscscan.com/tx/${tx.hash}`;
      console.log(`Successful panic at ${url}`);
    } catch (err) {
      console.log(`Could not panic due to: ${err}`);
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
