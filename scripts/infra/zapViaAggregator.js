const hardhat = require("hardhat");
const ethers = hardhat.ethers;
import { addressBook } from "blockchain-addressbook";
import fetch from 'node-fetch';

const {
    platforms: { beefyfinance },
    tokens: {
      USDC: token,
    },
  } = addressBook.polygon;

const config = {
  vault:  "0x15FC2BA59956564b39Eba06DCd6a37F4476f1eD5",
  token: token.address,
  amount: ethers.utils.parseUnits("7", token.decimals),
  withdraw: true,
  reinvest: true,
  reinvestVault: "0x03F69AAF4c8512f533Da46cC9eFd49C4969e3CB8",
  network: "polygon",
};

const emptyBytes = ethers.utils.formatBytes32String(0);

const abi = [
    'function beefIn(address beefyVault, address inputToken, uint256 tokenInAmount, bytes memory token0, bytes memory token1) external',
    'function beefOutAndSwap(address beefyVault, uint256 withdrawAmount, address desiredToken, bytes memory dataToken0, bytes memory dataToken1) external',
    'function quoteRemoveLiquidity(address beefyVault, uint256 mooTokenAmt) external view returns (uint256 amt0, uint256 amt1, address token0, address token1)',
    'function quoteStableAddLiquidityRatio(address beefyVault) external view returns (uint)',
    'function beefOutAndReInvest(address fromVault, address toVault, uint256 mooTokenAmount, bytes memory token0ToFrom, bytes memory token1ToFrom) external'
];

const ercAbi = [
    'function balanceOf(address) external view returns (uint)',
    'function allowance(address owner, address spender) external view returns (uint)',
    'function approve(address spender, uint256 value) external',
    'function name() external view returns (string)',
    'function symbol() external view returns (string)',
    'function want() external view returns (address)',
    'function decimals() external view returns (uint)',
    'function getPricePerFullShare() external view returns (uint)',
    'function strategy() external view returns (address)'
];

const strategyAbi = [
    'function withdrawalFee() external view returns (uint)'
]

const uniV2Pair = [
    'function token0() external view returns (address)',
    'function token1() external view returns (address)',
    'function stable() external view returns (bool)'
];

let chainId;
let etherscanLink;
let zap; 
switch (config.network) {
    case "polygon":
        chainId = 137;
        etherscanLink = "polygonscan.com";
        zap = "0x41e2F0104B7237CBFC0238d902Ef37a07Be068A5";
        break;
    case "bsc":
        chainId = 56;
        etherscanLink = "bscscan.com";
        break;    
}

async function main() {

    const [deployer] = await ethers.getSigners();
    const zapContract = new ethers.Contract(zap, abi, deployer);

    if (config.withdraw) {
      if(!config.reinvest) {
        console.log('Creating BeefOutAndSwap transaction...')
        const mooTokenContract = new ethers.Contract(config.vault, ercAbi, deployer);
        const name = await mooTokenContract.name();
        const want = await mooTokenContract.want();
        const wantContract = new ethers.Contract(want, uniV2Pair, deployer);

        let token0;
        let token1;
        let token0Contract;
        let token0Decimals;
        let token1Contract;
        let token1Decimals;
        let single = false
        try {
            token0 = await wantContract.token0();
            token1 = await wantContract.token1();
            token0Contract = new ethers.Contract(token0, ercAbi, deployer);
            token0Decimals = await token0Contract.decimals();
            token1Contract = new ethers.Contract(token1, ercAbi, deployer);
            token1Decimals = await token1Contract.decimals();
        } catch (e) {
            token0 = want;
            token1 = ethers.constants.AddressZero;
            token0Contract = new ethers.Contract(token0, ercAbi, deployer);
            token0Decimals = await token0Contract.decimals();
            single = true;
        }

        const tokenContract = new ethers.Contract(config.token, ercAbi, deployer);
        const tokenName = await tokenContract.symbol();
        const tokenDecimals = await tokenContract.decimals();
        const balance = await mooTokenContract.balanceOf(deployer.address);
        const allowance = await mooTokenContract.allowance(deployer.address, zap);
        console.log(`Vault Name: ${name}.`);
        console.log(`Want Address: ${config.token}.`);
        console.log(`Allowance of ${allowance.toString()} and Total Request to Withdraw of ${balance.toString()}.`);
        if (balance.gte(allowance)) {
            console.log('Starting approval...')
            let approveZeroTx = await mooTokenContract.approve(zap, 0);
            approveZeroTx = await approveZeroTx.wait();
            console.log(`Approved Zero.`);
            let approveTx = await mooTokenContract.approve(zap, ethers.constants.MaxUint256);
            approveTx = await approveTx.wait();
            console.log(`Approved Max.`);
        } else {
            console.log(`Sufficient Approval.`)
        }

        let removeLiquidityData;
        if (!single) {
            removeLiquidityData = await zapContract.quoteRemoveLiquidity(config.vault, BigInt(balance.toString()));
        } else {
            const strategy = await mooTokenContract.strategy();
            const strategyContract = new ethers.Contract(strategy, strategyAbi, deployer);
            const withdrawFee = await strategyContract.withdrawalFee()
            const ppfs = await mooTokenContract.getPricePerFullShare();
            const fee = balance.mul(withdrawFee).div(10000);
            console.log(ppfs.toString());
            const amt = balance.sub(fee).mul(ppfs).div(ethers.constants.WeiPerEther);
            console.log(amt.toString())
            removeLiquidityData = { token0: want, amt0: amt}
        }
    
        let tokenData0 = {tx: { data: emptyBytes }}; 
        if (removeLiquidityData.token0.toString() != config.token) {
            const response0 = await fetch(`https://api.1inch.io/v4.0/${chainId}/swap?fromTokenAddress=${removeLiquidityData.token0}&toTokenAddress=${config.token}&amount=${removeLiquidityData.amt0}&fromAddress=${zap}&slippage=1&disableEstimate=true`);
            tokenData0 = await response0.json();


            const swapAmt0 = ethers.utils.formatUnits(BigInt(removeLiquidityData.amt0), token0Decimals.toString());
            const swapToAmt0 = ethers.utils.formatUnits(tokenData0.toTokenAmount, tokenDecimals.toString());
            console.log(`Swapping from ${swapAmt0} ${tokenData0.fromToken.symbol} to ${swapToAmt0} ${tokenData0.toToken.symbol}.`);
        }

        let tokenData1 = {tx: { data: emptyBytes }};
        if (token1.toString() != config.token && token1 != ethers.constants.AddressZero) {
            const response1 = await fetch(`https://api.1inch.io/v4.0/${chainId}/swap?fromTokenAddress=${removeLiquidityData.token1}&toTokenAddress=${config.token}&amount=${removeLiquidityData.amt1}&fromAddress=${zap}&slippage=1&disableEstimate=true`);
            tokenData1 = await response1.json();

            const swapAmt1 = ethers.utils.formatUnits(BigInt(removeLiquidityData.amt1), token1Decimals.toString());
            const swapToAmt1 = ethers.utils.formatUnits(tokenData1.toTokenAmount, tokenDecimals.toString());
            console.log(`Swapping from ${swapAmt1} ${tokenData1.fromToken.symbol} to ${swapToAmt1} ${tokenData1.toToken.symbol}.`);
        }

        const zapAmt = ethers.utils.formatUnits(BigInt(balance), 18);
        let withdrawTx = await zapContract.beefOutAndSwap(config.vault, BigInt(balance.toString()), config.token, tokenData0.tx.data, tokenData1.tx.data);
        withdrawTx = await withdrawTx.wait();
        console.log(`Zapped out ${zapAmt} from ${name} to ${tokenName}.`);
        console.log(`Transaction Reciept:`);
        console.log(`https://${etherscanLink}/tx/${withdrawTx.transactionHash}`);
      } else {
        console.log('Creating BeefOutAndReinvest transaction...')
        const mooTokenContract = new ethers.Contract(config.vault, ercAbi, deployer);
        const toMooTokenContract = new ethers.Contract(config.reinvestVault, ercAbi, deployer);
        const name = await mooTokenContract.name();
        const toName = await toMooTokenContract.name();
        const want = await mooTokenContract.want();
        const toWant = await toMooTokenContract.want();
        const wantContract = new ethers.Contract(want, uniV2Pair, deployer);
        const toWantContract = new ethers.Contract(toWant, uniV2Pair, deployer);

        let token0;
        let token1;
        let token0Contract;
        let token0Decimals;
        let token1Contract;
        let token1Decimals;
        let single = false
        try {
            token0 = await wantContract.token0();
            token1 = await wantContract.token1();
            token0Contract = new ethers.Contract(token0, ercAbi, deployer);
            token0Decimals = await token0Contract.decimals();
            token1Contract = new ethers.Contract(token1, ercAbi, deployer);
            token1Decimals = await token1Contract.decimals();
        } catch (e) {
            token0 = want;
            token1 = want;
            token0Contract = new ethers.Contract(token0, ercAbi, deployer);
            token0Decimals = await token0Contract.decimals();
            token1Decimals = token0Decimals;
            single = true;
        }

        let toToken0;
        let toToken1;
        let toToken0Contract;
        let toToken0Decimals;
        let toToken1Contract;
        let toToken1Decimals;
        try {
            toToken0 = await toWantContract.token0();
            toToken1 = await toWantContract.token1();
            toToken0Contract = new ethers.Contract(toToken0, ercAbi, deployer);
            toToken0Decimals = await toToken0Contract.decimals();
            toToken1Contract = new ethers.Contract(toToken1, ercAbi, deployer);
            toToken1Decimals = await toToken1Contract.decimals();
        } catch (e) {
            toToken0 = toWant;
            toToken1 = toWant;
            toToken0Contract = new ethers.Contract(toToken0, ercAbi, deployer);
            toToken0Decimals = await toToken0Contract.decimals();
            toToken1Decimals = toToken0Decimals;
        }

        const balance = await mooTokenContract.balanceOf(deployer.address);
        const allowance = await mooTokenContract.allowance(deployer.address, zap);
        console.log(`Vault Name From: ${name}.`);
        console.log(`Vault Name To: ${toName}`)
        console.log(`Want Address From: ${want}.`);
        console.log(`Want Address To: ${toWant}`);
        console.log(`Allowance of ${allowance.toString()} and Total Request to Withdraw of ${balance.toString()}.`);
        if (balance.gte(allowance)) {
            console.log('Starting approval...')
            let approveZeroTx = await mooTokenContract.approve(zap, 0);
            approveZeroTx = await approveZeroTx.wait();
            console.log(`Approved Zero.`);
            let approveTx = await mooTokenContract.approve(zap, ethers.constants.MaxUint256);
            approveTx = await approveTx.wait();
            console.log(`Approved Max.`);
        } else {
            console.log(`Sufficient Approval.`)
        }

        let removeLiquidityData;
        if (!single) {
            removeLiquidityData = await zapContract.quoteRemoveLiquidity(config.vault, BigInt(balance.toString()));
        } else {
            const strategy = await mooTokenContract.strategy();
            const strategyContract = new ethers.Contract(strategy, strategyAbi, deployer);
            const withdrawFee = await strategyContract.withdrawalFee()
            const ppfs = await mooTokenContract.getPricePerFullShare();
            const fee = balance.mul(withdrawFee).div(10000).add(1);
            const amt = balance.sub(fee).mul(ppfs).div(ethers.constants.WeiPerEther);
            const amount0 = amt.div(2);
            const amount1 = amt.sub(amount0);
            removeLiquidityData = { token0: want, token1: want, amt0: amount0, amt1: amount1};
        }

        let tokenData0 = {tx: { data: emptyBytes }}; 
        if (token0.toString() != toToken0.toString()) {
            const response0 = await fetch(`https://api.1inch.io/v4.0/${chainId}/swap?fromTokenAddress=${removeLiquidityData.token0}&toTokenAddress=${toToken0}&amount=${removeLiquidityData.amt0}&fromAddress=${zap}&slippage=1&disableEstimate=true`);
            tokenData0 = await response0.json();

            const swapAmt0 = ethers.utils.formatUnits(BigInt(removeLiquidityData.amt0), token0Decimals.toString());
            const swapToAmt0 = ethers.utils.formatUnits(tokenData0.toTokenAmount, toToken0Decimals.toString());
            console.log(`Swapping from ${swapAmt0} ${tokenData0.fromToken.symbol} to ${swapToAmt0} ${tokenData0.toToken.symbol}.`);
        }

        let tokenData1 = {tx: { data: emptyBytes }};
        if (token1.toString() != toToken1.toString() && token1 != toToken1) {
            const response1 = await fetch(`https://api.1inch.io/v4.0/${chainId}/swap?fromTokenAddress=${removeLiquidityData.token1}&toTokenAddress=${toToken1}&amount=${removeLiquidityData.amt1}&fromAddress=${zap}&slippage=1&disableEstimate=true`);
            tokenData1 = await response1.json();

            const swapAmt1 = ethers.utils.formatUnits(BigInt(removeLiquidityData.amt1), token1Decimals.toString());
            const swapToAmt1 = ethers.utils.formatUnits(tokenData1.toTokenAmount, toToken1Decimals.toString());
            console.log(`Swapping from ${swapAmt1} ${tokenData1.fromToken.symbol} to ${swapToAmt1} ${tokenData1.toToken.symbol}.`);
        }

        const zapAmt = ethers.utils.formatUnits(BigInt(balance), 18);
        let withdrawTx = await zapContract.beefOutAndReInvest(config.vault, config.reinvestVault, BigInt(balance.toString()), tokenData0.tx.data, tokenData1.tx.data);
        withdrawTx = await withdrawTx.wait();
        console.log(`Zapped out ${zapAmt} from ${name} and Zapped into ${toName}.`);
        console.log(`Transaction Reciept:`);
        console.log(`https://${etherscanLink}/tx/${withdrawTx.transactionHash}`);
      }

    } else {
        console.log('Creating BeefIn transaction...')
        const fromTokenContract = new ethers.Contract(config.token, ercAbi, deployer);
        const mooTokenContract = new ethers.Contract(config.vault, ercAbi, deployer);
        const name = await mooTokenContract.name();
        const want = await mooTokenContract.want();
        const wantContract = new ethers.Contract(want, uniV2Pair, deployer);
        const allowance = await fromTokenContract.allowance(deployer.address, zap);
        const fromName = await fromTokenContract.symbol();
        const fromDecimals = await fromTokenContract.decimals();
        
        let token0;
        let token1;
        let single = false
        try {
            token0 = await wantContract.token0();
            token1 = await wantContract.token1();
        } catch (e) {
            token0 = want;
            token1 = ethers.constants.AddressZero;
            single = true;
        }

        console.log(`Vault Name: ${name}.`);
        console.log(`Want Address: ${want}.`);
        console.log(`Allowance of ${allowance.toString()} and Total Request Deposit of ${config.amount}.`);

        if (config.amount.gte(allowance)) {
            console.log('Starting approval...');
            let approveZeroTx = await fromTokenContract.approve(zap, 0);
            approveZeroTx = await approveZeroTx.wait();
            console.log(`Approved Zero.`);
            let approveTx = await fromTokenContract.approve(zap, ethers.constants.MaxUint256);
            approveTx = await approveTx.wait();
            console.log(`Approved Max.`);
        } else {
            console.log(`Sufficient Approval.`);
        }

        let stable = false;
      
        try {
            stable = await wantContract.stable();
            stable == true ? console.log('Stable pair getting the ratio needed for swap...') : console.log('Solidly Volatile Pair');
          } catch (e) {}

        

        let amt0;
        let amt1;
        if (!single) {
            amt0 = config.amount.div(2);
            amt1 = config.amount.sub(amt0);
            if(stable) {
                const ratio = await zapContract.quoteStableAddLiquidityRatio(config.vault);
                amt0 = config.amount.mul((ethers.constants.WeiPerEther.sub(ratio)).div(ethers.constants.WeiPerEther));
                amt1 = config.amount.sub(amt0);
            }
        } else {
            amt0 = config.amount;
        }

        let tokenData0 = {tx: { data: emptyBytes }};
        if (token0.toString() != config.token) {
            const response0 = await fetch(`https://api.1inch.io/v4.0/${chainId}/swap?fromTokenAddress=${config.token}&toTokenAddress=${token0}&slippage=1&amount=${amt0}&&fromAddress=${zap}&disableEstimate=true`);
            tokenData0 = await response0.json();

            const swapAmt0 = ethers.utils.formatUnits(BigInt(amt0), fromDecimals.toString());
            console.log(`Swapping from ${swapAmt0} ${tokenData0.fromToken.symbol} to ${tokenData0.toToken.symbol}.`);
        }

        let tokenData1 = {tx: { data: emptyBytes }};
        if (token1.toString() != config.token && token1 != ethers.constants.AddressZero) {
            const response1 = await fetch(`https://api.1inch.io/v4.0/${chainId}/swap?fromTokenAddress=${config.token}&toTokenAddress=${token1}&slippage=1&amount=${amt1}&fromAddress=${zap}&disableEstimate=true`);
            tokenData1 = await response1.json();

            const swapAmt1 = ethers.utils.formatUnits(BigInt(amt1), fromDecimals.toString())
            console.log(`Swapping from ${swapAmt1} ${tokenData1.fromToken.symbol} to ${tokenData1.toToken.symbol}.`);
        }

        const zapAmt = ethers.utils.formatUnits(BigInt(config.amount), fromDecimals.toString());
        let depositTx = await zapContract.beefIn(config.vault, config.token, BigInt(config.amount), tokenData0.tx.data, tokenData1.tx.data);
        depositTx = await depositTx.wait();
        console.log(`Zapped in ${zapAmt} ${fromName} to ${name}.`);
        console.log(`Transaction Reciept:`);
        console.log(`https://${etherscanLink}/tx/${depositTx.transactionHash}`);
    }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });