import hardhat from "hardhat";

export const verifyContract = async (address: string, constructorArguments: any[]) => {
  return hardhat.run("verify:verify", {
    address,
    constructorArguments,
  });
};
