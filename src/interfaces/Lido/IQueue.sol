// SPDX-License-Identifier: MIT

pragma solidity >=0.6.12;

interface IQueue {
    function requestWithdrawals(uint256[] calldata _amounts, address _owner) external returns (uint256[] memory requestIds);
    function claimWithdrawal(uint256 _requestId) external;
}

