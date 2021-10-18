import hardhat from "hardhat";
import { DeployFunction, DeployOptions, DeployResult } from "hardhat-deploy/types";
import { addressBook } from "blockchain-addressbook";
import { verifyContract } from "../../utils/verifyContract";

const {
  BIFI: { address: BIFI },
  WFTM: { address: WFTM },
} = addressBook.fantom.tokens;
const { spookyswap } = addressBook.fantom.platforms;

const shouldVerifyOnEtherscan = false;

const params = {
  bifiMaxiVaultAddress: "0xbF07093ccd6adFC3dEB259C557b61E94c1F66945",
  unirouter: spookyswap.router,
  nativeToNativeRoute: [WFTM, BIFI],
};

const contractNames = {
  strategistBuyback: "StrategistBuyback",
};

const deployStrategistBuyback: DeployFunction = async hardhatEnv => {
  if (Object.values(params).some(v => v === undefined) || Object.values(contractNames).some(v => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const [deployer] = await hardhatEnv.getUnnamedAccounts();
  console.log(`Deploying ${contractNames.strategistBuyback} using deployer: ${deployer}`);

  const deployOptions: DeployOptions = {
    from: deployer,
    proxy: true,
    args: [params.bifiMaxiVaultAddress, params.unirouter, params.nativeToNativeRoute],
  };
  const strategistBuyback: DeployResult = await hardhatEnv.deployments.deploy(
    contractNames.strategistBuyback,
    deployOptions
  );

  console.log();
  console.log(`StrategistBuyback: ${strategistBuyback.address}`);

  console.log();
  console.log("Running post deployment");

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    console.log(`Verifying ${contractNames.strategistBuyback}`);
    verifyContractsPromises.push(verifyContract(strategistBuyback.address, deployOptions.args));
  }
  console.log();

  await Promise.all(verifyContractsPromises);
};

deployStrategistBuyback(hardhat)
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
