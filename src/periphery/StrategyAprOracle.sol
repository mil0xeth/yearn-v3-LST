// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {AprOracleBase} from "@periphery/AprOracle/AprOracleBase.sol";

contract StrategyAprOracle is AprOracleBase {

    uint256 public apr;
    
    constructor() AprOracleBase("Fixed Apr Oracle", msg.sender) {
    }

    function aprAfterDebtChange(
        address /*_asset*/,
        int256 /*_delta*/
    ) external view override returns (uint256) {
        return apr;
    }

    /**
    @notice Update the APR.
    @param _apr APR in 1e18, i.e. 1e18 == 100% APR, 1e17 == 10% APR.
    */
    function updateApr(uint256 _apr) external onlyGovernance {
        apr = _apr;
    }
}
