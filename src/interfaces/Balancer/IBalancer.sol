// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

interface IBalancer {
    struct SingleSwap {
        bytes32 poolId;
        uint8 kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }
    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }
    function swap(
        SingleSwap memory singleSwap,
        FundManagement memory funds,
        uint256 limit,
        uint256 deadline
    ) external payable returns (uint256);
}

interface IBalancerPool{
    function getPoolId() external view returns (bytes32);
    function getPrice() external view returns (uint256);
}
