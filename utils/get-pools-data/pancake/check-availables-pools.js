const fs = require('fs');
const path = require('path');
const axios = require('axios');
const pools = require('./pools.json');

async function main() {

  await getAvailablePools()
  
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


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });