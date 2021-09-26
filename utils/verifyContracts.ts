import hardhat from "hardhat";
import { Contract } from "@ethersproject/contracts";

export const verifyContracts = async (
  vault: Contract,
  vaultConstructorArguments: any[],
  strategy: Contract,
  strategyConstructorArguments: any[]
) => {
  await hardhat.run("verify:verify", {
    address: vault.address,
    constructorArguments: vaultConstructorArguments,
  });

  await hardhat.run("verify:verify", {
    address: strategy.address,
    constructorArguments: strategyConstructorArguments,
  });
};
