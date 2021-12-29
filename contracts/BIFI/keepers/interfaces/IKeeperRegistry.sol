// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

interface IKeeperRegistry {
    event ConfigSet(
        uint32 paymentPremiumPPB,
        uint24 blockCountPerTurn,
        uint32 checkGasLimit,
        uint24 stalenessSeconds,
        uint16 gasCeilingMultiplier,
        uint256 fallbackGasPrice,
        uint256 fallbackLinkPrice
    );
    event FlatFeeSet(uint32 flatFeeMicroLink);
    event FundsAdded(uint256 indexed id, address indexed from, uint96 amount);
    event FundsWithdrawn(uint256 indexed id, uint256 amount, address to);
    event KeepersUpdated(address[] keepers, address[] payees);
    event OwnershipTransferRequested(address indexed from, address indexed to);
    event OwnershipTransferred(address indexed from, address indexed to);
    event Paused(address account);
    event PayeeshipTransferRequested(address indexed keeper, address indexed from, address indexed to);
    event PayeeshipTransferred(address indexed keeper, address indexed from, address indexed to);
    event PaymentWithdrawn(address indexed keeper, uint256 indexed amount, address indexed to, address payee);
    event RegistrarChanged(address indexed from, address indexed to);
    event Unpaused(address account);
    event UpkeepCanceled(uint256 indexed id, uint64 indexed atBlockHeight);
    event UpkeepPerformed(
        uint256 indexed id,
        bool indexed success,
        address indexed from,
        uint96 payment,
        bytes performData
    );
    event UpkeepRegistered(uint256 indexed id, uint32 executeGas, address admin);

    function FAST_GAS_FEED() external view returns (address);

    function LINK() external view returns (address);

    function LINK_ETH_FEED() external view returns (address);

    function acceptOwnership() external;

    function acceptPayeeship(address keeper) external;

    function addFunds(uint256 id, uint96 amount) external;

    function cancelUpkeep(uint256 id) external;

    function checkUpkeep(uint256 id, address from)
        external
        returns (
            bytes memory performData,
            uint256 maxLinkPayment,
            uint256 gasLimit,
            uint256 adjustedGasWei,
            uint256 linkEth
        );

    function getCanceledUpkeepList() external view returns (uint256[] memory);

    function getConfig()
        external
        view
        returns (
            uint32 paymentPremiumPPB,
            uint24 blockCountPerTurn,
            uint32 checkGasLimit,
            uint24 stalenessSeconds,
            uint16 gasCeilingMultiplier,
            uint256 fallbackGasPrice,
            uint256 fallbackLinkPrice
        );

    function getFlatFee() external view returns (uint32);

    function getKeeperInfo(address query)
        external
        view
        returns (
            address payee,
            bool active,
            uint96 balance
        );

    function getKeeperList() external view returns (address[] memory);

    function getMaxPaymentForGas(uint256 gasLimit) external view returns (uint96 maxPayment);

    function getMinBalanceForUpkeep(uint256 id) external view returns (uint96 minBalance);

    function getRegistrar() external view returns (address);

    function getUpkeep(uint256 id)
        external
        view
        returns (
            address target,
            uint32 executeGas,
            bytes memory checkData,
            uint96 balance,
            address lastKeeper,
            address admin,
            uint64 maxValidBlocknumber
        );

    function getUpkeepCount() external view returns (uint256);

    function onTokenTransfer(
        address sender,
        uint256 amount,
        bytes memory data
    ) external;

    function owner() external view returns (address);

    function pause() external;

    function paused() external view returns (bool);

    function performUpkeep(uint256 id, bytes memory performData) external returns (bool success);

    function recoverFunds() external;

    function registerUpkeep(
        address target,
        uint32 gasLimit,
        address admin,
        bytes memory checkData
    ) external returns (uint256 id);

    function setConfig(
        uint32 paymentPremiumPPB,
        uint32 flatFeeMicroLink,
        uint24 blockCountPerTurn,
        uint32 checkGasLimit,
        uint24 stalenessSeconds,
        uint16 gasCeilingMultiplier,
        uint256 fallbackGasPrice,
        uint256 fallbackLinkPrice
    ) external;

    function setKeepers(address[] memory keepers, address[] memory payees) external;

    function setRegistrar(address registrar) external;

    function transferOwnership(address to) external;

    function transferPayeeship(address keeper, address proposed) external;

    function typeAndVersion() external view returns (string memory);

    function unpause() external;

    function withdrawFunds(uint256 id, address to) external;

    function withdrawPayment(address from, address to) external;
}
