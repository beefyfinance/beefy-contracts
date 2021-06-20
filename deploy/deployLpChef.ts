'use strict';

import hre, { ethers } from "hardhat";
import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";

import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction, DeployOptions } from 'hardhat-deploy/types';

import "../utils/registerSubsidy";
import "../utils/hardhatRPC";
import { contractAddressGenerator } from "../utils/predictAddresses";

import vaults from "../deployData/LpChef";
import chainSettings from "../deployData/chains";
import { addressBook, ChainId } from "blockchain-addressbook";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signers";

import {
    BeefyVaultV6,
    BeefyVaultV6__factory,
    StrategyCommonChefLP,
    StrategyCommonChefLP__factory
 } from "../typechain";

const VAULT_CONTRACT = "BeefyVaultV6";
const STRAT_CONTRACT = "StrategyCommonChefLP";

type VaultConstructorParams = Parameters<BeefyVaultV6__factory["deploy"]>;
type StratConstructorParams = Parameters<StrategyCommonChefLP__factory["deploy"]>;

function getDeployOptions<P extends any[]>(deployer: SignerWithAddress, contract: string, args:P, skipIfAlreadyDeployed:boolean = true) {
    return {
        from: deployer.address,
        contract: contract,
        args: args,
        skipIfAlreadyDeployed: skipIfAlreadyDeployed,
        log: true
    } as DeployOptions;
}

const deployAllVaults: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    let vaultDeployOptions:DeployOptions | null = null;
    let stratDeployOptions:DeployOptions | null = null;
    try {
        const { deploy, execute, read, fetchIfDifferent } = hre.deployments;

        const deployer = await hre.ethers.getNamedSigner('deployer');
        console.log(`Deployer: ${deployer.address}\n`);

        const chainConfig = chainSettings[hre.network.config.chainId as ChainId];
        const beefyfinance = addressBook[hre.network.config.chainId as ChainId].platforms.beefyfinance;

        for (const vault in vaults) {
            const config = vaults[vault];
            if (config.chainId != hre.network.config.chainId) continue;

            const contractAddress = await contractAddressGenerator(deployer);

            const mooName = `Moo ${config.platform} ${config.lp0.symbol}-${config.lp1.symbol}`;
            const mooSymbol = `moo${config.platform}${config.lp0.symbol}-${config.lp1.symbol}`;
            const vaultName = `${mooName} Vault`;
            const stratName = `${mooName} Strategy`

            let vaultParams:VaultConstructorParams = [
                '0xStrategy',
                mooName,
                mooSymbol,
                21600,
            ]

            let strategyParams:StratConstructorParams = [
                config.want,
                config.poolId,
                config.chef,
                '0xVault',
                config.unirouter,
                beefyfinance.keeper,
                config.strategist,
                beefyfinance.beefyFeeRecipient,
                config.outputToNativeRoute,
                config.outputToLp0Route,
                config.outputToLp1Route
            ];

            let deployedVault = await hre.deployments.getOrNull(vaultName);
            //if (deployedVault) console.debug(`Found existing deployment for "${vaultName}"`);
            let deployedStrat = await hre.deployments.getOrNull(stratName);
            //if (deployedStrat) console.debug(`Found existing deployment for "${stratName}"`);

            let vaultDeployOptions:DeployOptions | null = null;
            let stratDeployOptions:DeployOptions | null = null;

            let differences = false;

            if (deployedVault && deployedStrat) {
                vaultParams[0] = deployedStrat.address;
                strategyParams[3] = deployedVault.address;

                vaultDeployOptions = getDeployOptions<VaultConstructorParams>(deployer, VAULT_CONTRACT, vaultParams, false);
                stratDeployOptions = getDeployOptions<StratConstructorParams>(deployer, STRAT_CONTRACT, strategyParams, false);

                if ((await fetchIfDifferent(vaultName, vaultDeployOptions)).differences
                    || (await fetchIfDifferent(stratName, stratDeployOptions)).differences
                    ) {
                    deployedVault = null;
                    deployedStrat = null;
                    differences = true;
                }
            }

            if (!deployedVault || !deployedStrat) {
                strategyParams[3] = (await contractAddress.next()).value as string;
                vaultParams[0] = (await contractAddress.next()).value as string;
                vaultDeployOptions = getDeployOptions<VaultConstructorParams>(deployer, VAULT_CONTRACT, vaultParams);
                stratDeployOptions = getDeployOptions<StratConstructorParams>(deployer, STRAT_CONTRACT, strategyParams);
            }

            if (vaultDeployOptions === null) throw "Impossible";
            if (stratDeployOptions === null) throw "Impossible";

            const vaultDeployResult = await deploy(vaultName, vaultDeployOptions);
            const stratDeployResult = await deploy(stratName, stratDeployOptions);

            if (differences) {
                console.warn(`config or bytecode for "${mooName}" do not match deployment`);
            }

            // Update settings
            const vaultContract = await ethers.getContractAt<BeefyVaultV6>(vaultDeployResult.abi, vaultDeployResult.address);
            const stratContract = await ethers.getContractAt<StrategyCommonChefLP>(stratDeployResult.abi, stratDeployResult.address);

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

            // Set wichdrawl fee
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
    }
    catch (e) {
        console.error(e);
        console.debug(vaultDeployOptions);
        console.debug(stratDeployOptions);
    }
};
export default deployAllVaults;