#! /bin/sh

function usage() {
    cat <<USAGE

    Usage: $0 [-ps pool-start] [-pe pool-end] [-p platform] [-c chain-name]

    Options:
        -ps, --pool-start:       Pool id number from start iteration, by default is "10"
        -pe, --pool-end:         Pool id number until iterate, by default is platform pool id length
        -p, --platform:          Plaform name, by default is "pancakeswap"
        -c, --chain-name:        Chain name, by default is "bsc"
        -n, --network:           Network name, by default is "localhost"
        -s, --skip-check:        Skip check if already deployed

USAGE
    exit 1
}

function gen_log_file {
    isodate=$(date -u +%Y-%m-%dT%H-%M-%SZ)
    echo "$(dirname ${0})/logs/iterator/$PLATFORM-$CHAIN_NAME-${isodate}.txt"
}

function iterate {
    POOL_ID_END=${POOL_ID_END:-"$(expr $(npx hardhat run $(dirname ${0})/get-pool-length.js ) - 1)"}

    if [[ $POOL_ID_START -gt $POOL_ID_END ]]
    then
        echo "Error trying to iterate over pool id: $POOL_ID_START"
        echo "$PLATFORM pool length is $POOL_ID_END , should be choose a lower number"
        exit
    fi

    echo "====> Iterating from $POOL_ID_START to $POOL_ID_END on $PLATFORM"

    for pool in $(seq $POOL_ID_START $POOL_ID_END)
    do 
        export POOL_ID=$pool && yarn run test:automation:iterate --network $NETWORK
    done
}


# Run script start here
if [ $# -eq 0 ]; then
    usage
fi

# Arguments variables and defaults
export POOL_ID_START=99
export PLATFORM="pancakeswap"
export CHAIN_NAME="bsc"
export POOL_ID_END
export SKIP_CHECK_DEPLOYED
NETWORK="localhost"

# Check arguments
while [ "$1" != "" ]; do
    case $1 in
    -ps | --pool-start)
        shift
        POOL_ID_START=$1
        ;;
    -pe | --pool-end)
        shift
        POOL_ID_END=$1
        ;;
    -p | --platform)
        shift
        PLATFORM=$1
        ;;
    -c | --chain-name)
        shift
        CHAIN_NAME=$1
        ;;
    -n | --network)
        shift
        NETWORK=$1
        ;;
    -s | --skip-check)
        shift
        SKIP_CHECK_DEPLOYED=true
        ;;
    *)
        usage
        exit 1
        ;;
    esac
    shift
done

logfile=$(gen_log_file $PLATFORM $CHAIN_NAME)
iterate | tee -a $logfile
echo "\n\n\t Iteration end !"
