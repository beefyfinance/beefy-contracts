import hardhat, {ethers} from "hardhat";
import {predictAddresses} from "../../utils/predictAddresses";
import {setCorrectCallFee} from "../../utils/setCorrectCallFee";
import {verifyContracts} from "../../utils/verifyContracts";

// const registerSubsidy = require("../../utils/registerSubsidy");

const {
    vaultParams,
    strategyParams,
    shouldVerifyOnEtherscan
} = require('./vault-configs/dino');

const contractNames = {
    vault: "BeefyVaultV6",
    strategy: "StrategyDinoSingle",
};

async function main() {
    if (
        Object.values(vaultParams).some(v => v === undefined) ||
        Object.values(strategyParams).some(v => v === undefined) ||
        Object.values(contractNames).some(v => v === undefined)
    ) {
        console.error("one of config values undefined");
        return;
    }

    await hardhat.run("compile");

    const Vault = await ethers.getContractFactory(contractNames.vault);
    const Strategy = await ethers.getContractFactory(contractNames.strategy);

    const [deployer] = await ethers.getSigners();

    console.log("Deploying:", vaultParams.mooName);

    const predictedAddresses = await predictAddresses({creator: deployer.address});

    const vaultConstructorArguments = [
        predictedAddresses.strategy,
        vaultParams.mooName,
        vaultParams.mooSymbol,
        vaultParams.delay,
    ];
    const vault = await Vault.deploy(...vaultConstructorArguments);
    await vault.deployed();

    const strategyConstructorArguments = [
        strategyParams.want,
        strategyParams.rewardPool,
        vault.address,
        strategyParams.unirouter,
        strategyParams.keeper,
        strategyParams.strategist,
        strategyParams.beefyFeeRecipient,
        strategyParams.outputToNativeRoute,
    ];
    const strategy = await Strategy.deploy(...strategyConstructorArguments);
    await strategy.deployed();

    // add this info to PR
    console.log();
    console.log("Vault:", vault.address);
    console.log("Strategy:", strategy.address);
    console.log("Want:", strategyParams.want);
    console.log("RewardPool:", strategyParams.rewardPool);

    console.log();
    console.log("Running post deployment");

    if (shouldVerifyOnEtherscan) {
        await verifyContracts(vault, vaultConstructorArguments, strategy, strategyConstructorArguments);
    }
    await setCorrectCallFee(strategy, hardhat.network.name);
    console.log();
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
