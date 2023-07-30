// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";

interface IStrategyInterface is IStrategy {
    function balanceAsset() external view returns (uint256);
    function balanceLST() external view returns (uint256);
    function LST() external view returns (address);
    function pool() external view returns(address);
    function maxSingleTrade() external view returns (uint256);

    function setSwapSlippage(uint256) external;
    function setMaxSingleTrade(uint256) external;
}
