const fs = require('fs');

const ABI = {
    ERC20: require("../data/abi/ERC20.json"),
    masterchef: require("../data/abi/SushiMasterChef.json"),
    minichef: require("../data/abi/MiniChefV2.json"),
    LPPair: require("../data/abi/UniswapLPPair.json")
}

/**
 * Generate LP Pair object
 * @param {number} poolId - pool id number 
 * @param {address} deployer - deployer public address 
 * @param {address} chefAddress - chef address 
 * @param {ABI} masterchefABI - masterchef ABI json
 * @param {ABI} minichefABI - minichef ABI json
 * @param {ABI} LPPairABI - LP Pair ABI json
 * @returns object
 */
const getLpPair = async ({
    poolId,
    deployer,
    chefAddress,
    masterchefABI = ABI.masterchef,
    minichefABI = ABI.minichef,
    LPPairABI = ABI.LPPair
}) => {
    let chef = {
        type: '',
        contract: ''
    }
    let pool
    let lpAddress

    chef.type = await checkChefType(chefAddress, deployer)
    if (chef.type === 'master') {
        const contract = new ethers.Contract(chefAddress, masterchefABI, deployer);
        pool = await contract.poolInfo(poolId);
        lpAddress = ethers.utils.getAddress(pool.lpToken);
    } 
    if (chef.type === 'mini') {
        const contract = new ethers.Contract(chefAddress, minichefABI, deployer);
        pool = await contract.lpToken(poolId)
        lpAddress = ethers.utils.getAddress(pool);
    }
    const lpContract = new ethers.Contract(lpAddress, LPPairABI, deployer);
    let lpPair = {
        name: '',
        address: lpAddress,
        token0: {
            address: await lpContract.token0(),
            symbol: '',
            decimals: '',
        },
        token1: {
            address: await lpContract.token1(),
            symbol: '',
            decimals: '',
        },
        decimals: `1e${await lpContract.decimals()}`,
    };

    const token0Contract = new ethers.Contract(lpPair.token0.address, ABI.ERC20, deployer);
    lpPair.token0.symbol = await token0Contract.symbol();
    lpPair.token0.decimals = `1e${await token0Contract.decimals()}`;

    const token1Contract = new ethers.Contract(lpPair.token1.address, ABI.ERC20, deployer);
    lpPair.token1.symbol = await token1Contract.symbol();
    lpPair.token1.decimals = `1e${await token1Contract.decimals()}`;

    lpPair.name = `${lpPair.token0.symbol}-${lpPair.token1.symbol}`

    return lpPair
}

/**
 * Check which kind of Chef is
 * @param {Address} chefAddress - chef contract address
 * @returns {String} 'mini', 'master' or 'no detected'
 */
const checkChefType = async (chefAddress, deployer) => {
    let chef = 'No detected'
    try {
        const contract = new ethers.Contract(chefAddress, ABI.masterchef, deployer);
        const pool = await contract.poolInfo(0)
        if (ethers.utils.isAddress(pool.lpToken)) chef = 'master'
    } catch (error) {}
    try {
        const contract = new ethers.Contract(chefAddress, ABI.minichef, deployer);
        const pool = await contract.lpToken(0)
        if (ethers.utils.isAddress(pool)) chef = 'mini'
    } catch (error) {}
    return chef
}


/**
 * Resolve Swap Route
 * @param {address} input reward token
 * @param {array} proxies array with proxies token address
 * @param {address} preferredProxy 
 * @param {address} output 
 * @param {address} wnative 
 * @returns 
 */
const resolveSwapRoute = ({
    input,
    proxies,
    preferredProxy,
    output,
    wnative
}) => {
    if ([preferredProxy, output].includes(wnative)) { // Native pair
        if (output === wnative) return [wnative];
        return [wnative, output];
    }

    if (input === output) return [input];
    if (proxies.includes(output)) return [input, output];
    if (proxies.includes(preferredProxy)) return [input, preferredProxy, output];
    return [input, proxies.filter(input)[0], output]; // TODO: Choose the best proxy
}

/**
 * Writer - create a instance for a output log writer
 * @param {String} dirname output dirname
 * @param {String} [fileName] output filename - default 'ouput'
 * @param {timestamp} [timestamp] date time - default now
 */
const writer = ({
    dirname,
    filename = 'output',
    timestamp = Date.now()
}) => (data) => {
    if (dirname === undefined) throw new Error('no dirname argument passed')
    let time = new Date(timestamp).toISOString().replace(/(:|\.)/g, '-')
    fs.appendFileSync(`${dirname}/${filename}-${time}.txt`, data)
}

module.exports = {
    getLpPair,
    resolveSwapRoute,
    checkChefType,
    writer
}