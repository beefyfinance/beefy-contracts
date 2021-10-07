import hardhat from "hardhat";
import { Contract } from "@ethersproject/contracts";

export const verifyContracts = async (
  vaultConstructorArguments: any[],
  strategyConstructorArguments: any[]
) => {
  // await hardhat.run("verify:verify", {
  //   address: '0x91F88Edece02dbf868fc37D0a4621b82023b6504',
  //   constructorArguments: vaultConstructorArguments,
  // });

  await hardhat.run("verify:verify", {
    address: '0x9acf3e2BdDeBba68267d48FB35BD919407432A8F',
    constructorArguments: strategyConstructorArguments,
  });
};
