// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.9.0;

library UpkeepLibrary {
    uint256 public constant CHAINLINK_UPKEEPTX_PREMIUM_SCALING_FACTOR = 1 gwei;

    /**
     * @dev Rescues random funds stuck.
     */
    function _getCircularIndex(
        uint256 index_,
        uint256 offset_,
        uint256 bufferLength_
    ) internal pure returns (uint256 circularIndex_) {
        circularIndex_ = (index_ + offset_) % bufferLength_;
    }

    function _calculateUpkeepTxCost(
        uint256 gasprice_,
        uint256 gasOverhead_,
        uint256 chainlinkUpkeepTxPremiumFactor_
    ) internal pure returns (uint256 upkeepTxCost_) {
        upkeepTxCost_ =
            (gasprice_ * gasOverhead_ * chainlinkUpkeepTxPremiumFactor_) /
            CHAINLINK_UPKEEPTX_PREMIUM_SCALING_FACTOR;
    }

    function _calculateUpkeepTxCostFromTotalVaultHarvestOverhead(
        uint256 gasprice_,
        uint256 totalVaultHarvestOverhead_,
        uint256 keeperRegistryOverhead_,
        uint256 chainlinkUpkeepTxPremiumFactor_
    ) internal pure returns (uint256 upkeepTxCost_) {
        uint256 totalOverhead = totalVaultHarvestOverhead_ + keeperRegistryOverhead_;

        upkeepTxCost_ = _calculateUpkeepTxCost(gasprice_, totalOverhead, chainlinkUpkeepTxPremiumFactor_);
    }

    function _calculateProfit(uint256 revenue, uint256 expenses) internal pure returns (uint256 profit_) {
        profit_ = revenue >= expenses ? revenue - expenses : 0;
    }
}
