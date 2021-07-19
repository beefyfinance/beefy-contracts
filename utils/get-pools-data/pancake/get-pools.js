const path = require('path')
const fs = require('fs')
const {
  addressBook
} = require("blockchain-addressbook")
const {
  ethers
} = require("hardhat")

const _currentDir = __dirname.split('/').pop()

const MasterChefABI = require(`../../../contracts/BIFI/abi/${_currentDir}/MasterChef.json`)
const PancakePairABI = require(`../../../contracts/BIFI/abi/${_currentDir}/PancakePair.json`)
const ERC20ABI = require('../../../contracts/BIFI/abi/ERC20.json')

const masterchefAddress = addressBook.bsc.platforms.pancake.masterchef


async function sortPool() {
  const pools = require('./pools.json')
  fs.writeFileSync(`${__dirname}/pools-sorted.json`, '[\n')
  pools.sort((a, b) => a.poolId - b.poolId).map((p, index) => {
      if (index < pools.length - 1) {
          fs.appendFileSync(`${__dirname}/pools-sorted.json`, `${JSON.stringify(p)},\n`, {
              encoding: 'utf-8'
          })
      } else {
          fs.appendFileSync(`${__dirname}/pools-sorted.json`, `${JSON.stringify(p)}`, {
              encoding: 'utf-8'
          })
      }
  })
  fs.appendFileSync(`${__dirname}/pools-sorted.json`, '\n]')
  fs.renameSync(`${__dirname}/pools-sorted.json`, `${__dirname}/pools.json`)
}

async function getAvailablePools() {
  const pools = require('./pools.json')
  let { data: beefyApiPools } = await axios.get('https://raw.githubusercontent.com/beefyfinance/beefy-api/master/src/data/cakeLpPools.json')
  let availables = pools.filter( p => !(beefyApiPools.some( bp => bp.poolId == p.poolId)))
  console.log({availables});
  fs.writeFileSync(`${__dirname}/pools-availables.json`, '[\n')
  availables.map( (available, index) => {
    if (index < availables.length - 1) {
        fs.appendFileSync(`${__dirname}/pools-availables.json`, `${JSON.stringify(available)},\n`, {
            encoding: 'utf-8'
        })
    } else {
        fs.appendFileSync(`${__dirname}/pools-availables.json`, `${JSON.stringify(available)}`, {
            encoding: 'utf-8'
        })
    }
  })
  fs.appendFileSync(`${__dirname}/pools-availables.json`, '\n]')
}


async function main() {

  const signer = await ethers.getSigner();
  const masterchef = await new ethers.Contract(masterchefAddress, MasterChefABI, signer)
  let length = ethers.BigNumber.from(await masterchef.poolLength()).toNumber()

  // Check already pools in .json
  let alreadyPools = require('./pools.json')

  for (let poolId = 1; poolId <= length; poolId++) {
    try {
      if (alreadyPools.some( pool => pool.poolId == poolId)) continue
      let pool = {
        name: "",
        address: "",
        rewardPool: "",
        decimals: "",
        poolId,
        chainId: 56,
        lp0: {
          address: "",
          oracle: "tokens",
          oracleId: "",
          decimals: ""
        },
        lp1: {
          address: "",
          oracle: "tokens",
          oracleId: "",
          decimals: ""
        }
      }
      console.log("\n== getting poolId => ", poolId, " of ", length);
      let poolInfo = await masterchef.poolInfo(poolId)
      const pancakePair = await new ethers.Contract(poolInfo.lpToken, PancakePairABI, signer)
      pool.name = await pancakePair.name()
      if (pool.name.includes('LPs')) {
        console.log("poolId name:\t", pool.name);
        pool.symbol = await pancakePair.symbol()
        console.log("pool symbol:\t", pool.symbol);
        pool.decimals = `1e${await pancakePair.decimals()}`
        console.log("pool decimals:\t", pool.decimals);
        pool.lp0.address = await pancakePair.token0()
        console.log("token0:\t", pool.lp0.address);
        let token0 = await new ethers.Contract(pool.lp0.address, ERC20ABI, signer)
        pool.lp0.oracleId = (await token0.symbol()).toUpperCase()
        console.log("\t - oracleId:\t", pool.lp0.oracleId);
        pool.lp0.decimals = `1e${await token0.decimals()}`
        console.log("\t - decimals:\t", pool.lp0.decimals);

        pool.lp1.address = await pancakePair.token1()
        console.log("token1:\t", pool.lp1.address);
        let token1 = await new ethers.Contract(pool.lp1.address, ERC20ABI, signer)
        pool.lp1.oracleId = (await token1.symbol()).toUpperCase()
        console.log("\t - oracleId:\t", pool.lp1.oracleId);
        pool.lp1.decimals = `1e${await token1.decimals()}`
        console.log("\t - decimals:\t", pool.lp1.decimals);

        pool.name = `cakev2-${pool.lp0.oracleId.toLowerCase()}-${pool.lp1.oracleId.toLowerCase()}`
        console.log("pool name:\t", pool.name);

        fs.appendFileSync(`${__dirname}/pools-INPROCESS.json`, `${JSON.stringify(pool)},\n`)

      } else {
        console.log('Not has LPs => ', pool.name, ' next!')
      }

    } catch (error) {
      console.log('Shit happens', error)
      console.log('but we continue...')
    }
  }
  console.log('\n\nformating from pools-INPROCESS to pools.json =>');
  let inprocess = fs.readFileSync(`${__dirname}/pools-INPROCESS.json`, {
    encoding: 'utf-8'
  })
  fs.writeFileSync(`${__dirname}/pools.json`, `[${inprocess.slice(0, -2)}]`)

  console.log('Sorting pool.json')
  await sortPool()
  console.log('Creating list of available pools')
  await getAvailablePools()
  console.log('All Done!\nbye')

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });