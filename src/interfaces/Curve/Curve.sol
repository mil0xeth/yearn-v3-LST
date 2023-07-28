// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

interface ICurve {
    function exchange(
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external payable;

    function balances(uint256) external view returns (uint256);

    function get_dy(
        int128 from,
        int128 to,
        uint256 _from_amount
    ) external view returns (uint256);
    function A() external view returns (uint);
    function fee() external view returns (uint);
}
