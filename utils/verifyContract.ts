import hardhat from "hardhat";

export const verifyContract = async (address: string, constructorArguments: any[]) => {
  await hardhat.run("verify:verify", {
    address,
    constructorArguments,
  });
};
