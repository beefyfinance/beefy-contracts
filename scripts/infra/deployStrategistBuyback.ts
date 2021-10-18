import hardhat, { ethers } from "hardhat";
import { addressBook } from "blockchain-addressbook";
import { verifyContract } from "../../utils/verifyContract";

const {
  BIFI: { address: BIFI },
  WFTM: { address: WFTM },
} = addressBook.fantom.tokens;
const { spookyswap } = addressBook.fantom.platforms;

const shouldVerifyOnEtherscan = true;

const params = {
  bifiMaxiVaultAddress: "0xbF07093ccd6adFC3dEB259C557b61E94c1F66945",
  unirouter: spookyswap.router,
  nativeToNativeRoute: [WFTM, BIFI],
};

const contractNames = {
  strategistBuyback: "StrategistBuyback",
};

const deployStrategistBuyback = async () => {
  if (Object.values(params).some(v => v === undefined) || Object.values(contractNames).some(v => v === undefined)) {
    console.error("one of config values undefined");
    return;
  }

  await hardhat.run("compile");

  const StrategistBuyback = await ethers.getContractFactory(contractNames.strategistBuyback);

  console.log("Deploying:", contractNames.strategistBuyback);

  const constructorArguments = [params.bifiMaxiVaultAddress, params.unirouter, params.nativeToNativeRoute];
  const strategistBuyback = await StrategistBuyback.deploy(...constructorArguments);
  await strategistBuyback.deployed();

  console.log();
  console.log("StrategistBuyback:", strategistBuyback.address);

  console.log();
  console.log("Running post deployment");

  const verifyContractsPromises: Promise<any>[] = [];
  if (shouldVerifyOnEtherscan) {
    // skip await as this is a long running operation, and you can do other stuff to prepare vault while this finishes
    console.log(`Verifying ${contractNames.strategistBuyback}`);
    verifyContractsPromises.push(verifyContract(strategistBuyback, constructorArguments));
  }
  console.log();

  await Promise.all(verifyContractsPromises);
};

deployStrategistBuyback()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
