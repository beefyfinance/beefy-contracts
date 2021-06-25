'use strict';

import { HardhatRuntimeEnvironment } from 'hardhat/types';
import 'hardhat-deploy';
import '@nomiclabs/hardhat-ethers';

import { DeployOptions } from 'hardhat-deploy/types';

import "../utils/registerSubsidy";
import "../utils/hardhatRPC";
import { contractAddressGenerator } from "../utils/predictAddresses";

import { addressBook } from "blockchain-addressbook";
import chainSettings from "../deployData/chains";

import { BaseConfig } from "../deployData/types";
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';

function getDeployOptions(deployer: SignerWithAddress, contract: string, args: any[], skipIfAlreadyDeployed: boolean = true):DeployOptions {
    return {
        from: deployer.address,
        contract: contract,
        args: args,
        skipIfAlreadyDeployed: skipIfAlreadyDeployed,
        log: true
    };
}

async function deployVault(hre: HardhatRuntimeEnvironment, config: BaseConfig) {
    if (config.chainId != hre.network.config.chainId) return;

    let vaultDeployOptions: DeployOptions | null = null;
    let stratDeployOptions: DeployOptions | null = null;

    try {
        const { deploy, fetchIfDifferent } = hre.deployments;

        const deployerAddr = (await hre.getNamedAccounts())['deployer'];
        const deployer = await hre.ethers.getSigner(deployerAddr);

        const beefyfinance = addressBook[config.chainId].platforms.beefyfinance;

        const contractAddress = contractAddressGenerator(deployer) as AsyncGenerator<string,never,never>;

        const vaultName = `${config.platform}-${config.getWantSymbol()}-vault`.toLocaleLowerCase();
        const stratName = `${config.platform}-${config.getWantSymbol()}-strat`.toLocaleLowerCase();

        let deployedVault = await hre.deployments.getOrNull(vaultName);
        let deployedStrat = await hre.deployments.getOrNull(stratName);

        let vaultParams:ReturnType<typeof config.getVaultParams>;
        let strategyParams:ReturnType<typeof config.getStratParams>;

        let differences = false;

        if (deployedVault && deployedStrat) {
            vaultParams = config.getVaultParams(deployedStrat.address);
            strategyParams = config.getStratParams(deployedVault.address, beefyfinance.keeper, beefyfinance.beefyFeeRecipient);

            vaultDeployOptions = getDeployOptions(deployer, config.getVaultContract(), vaultParams, false);
            stratDeployOptions = getDeployOptions(deployer, config.getStratContract(), strategyParams, false);

            if ((await fetchIfDifferent(vaultName, vaultDeployOptions)).differences
                || (await fetchIfDifferent(stratName, stratDeployOptions)).differences
            ) {
                deployedVault = null;
                deployedStrat = null;
                differences = true;
            }
        }

        if (!deployedVault || !deployedStrat) {
            let vaultAddr = (await contractAddress.next()).value;
            let stratAddr = (await contractAddress.next()).value;

            vaultParams = config.getVaultParams(stratAddr);
            strategyParams = config.getStratParams(vaultAddr, beefyfinance.keeper, beefyfinance.beefyFeeRecipient);

            vaultDeployOptions = getDeployOptions(deployer, config.getVaultContract(), vaultParams);
            stratDeployOptions = getDeployOptions(deployer, config.getStratContract(), strategyParams);
        }

        const vaultDeployResult = await deploy(vaultName, vaultDeployOptions);
        const stratDeployResult = await deploy(stratName, stratDeployOptions);

        if (differences) {
            console.warn(`config or bytecode for "${config.getMooName()}" do not match deployment`);
        }

        // Update settings
        const vaultContract = await hre.ethers.getContractAt(vaultDeployResult.abi, vaultDeployResult.address);
        const stratContract = await hre.ethers.getContractAt(stratDeployResult.abi, stratDeployResult.address);

        // Set call fee
        {
            const chainCallFee = chainSettings[config.chainId].callFee;
            const curCallFee = await stratContract.callFee();
            if (!curCallFee.eq(chainCallFee)) {
                process.stdout.write(`  Setting call fee: ${chainCallFee}`);
                const tx = await stratContract.setCallFee(chainCallFee);
                process.stdout.write(` (tx: ${tx.hash})\n`);
                await tx.wait();
            }
        }

        // Set withdrawl fee
        if (config.withdrawalFee !== null && config.withdrawalFee !== undefined) {
            const curWithdrawlFee = await stratContract.withdrawalFee();
            if (!curWithdrawlFee.eq(config.withdrawalFee)) {
                process.stdout.write(`  Setting withdrawl fee: ${config.withdrawalFee}`);
                const tx = await stratContract.setWithdrawalFee(config.withdrawalFee);
                process.stdout.write(` (tx: ${tx.hash})\n`);
                await tx.wait();
            }
        }

        console.log();
    }
    catch (e) {
        console.error(e);
        console.debug(vaultDeployOptions);
        console.debug(stratDeployOptions);
    }
}
export default deployVault;