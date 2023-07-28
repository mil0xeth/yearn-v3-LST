// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/Lido/IWETH.sol";
import "./interfaces/Lido/ISTETH.sol";
import "./interfaces/Lido/IWSTETH.sol";
import {ICurve} from "./interfaces/Curve/Curve.sol";
import "./interfaces/Chainlink/AggregatorInterface.sol";

/// @title yearn-v3-LST-WETH
/// @author mil0x
/// @notice yearn-v3 Strategy that stakes asset into Liquid Staking Token (LST).
contract Strategy is BaseTokenizedStrategy {
    using SafeERC20 for ERC20;

    address public constant LST = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84; //STETH
    address public constant withdrawalQueueLST = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1; //STETH withdrawal queue
    // Use chainlink oracle to check latest LST/asset price
    AggregatorInterface public chainlinkOracle = AggregatorInterface(0x86392dC19c0b719886221c78AB11eb8Cf5c52812); //STETH/ETH

    address public curve = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022; //curve_ETH_STETH
    int128 internal constant ASSETID = 0;
    int128 internal constant LSTID = 1;

    // Parameters    
    uint256 public maxSingleTrade; //maximum amount that should be swapped in one go
    uint256 public swapSlippage; //actual slippage for a trade independent of the depeg; we check with chainlink for additional depeg

    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_BPS = 100_00;
    address internal constant gov = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52; //yearn governance

    constructor(address _asset, string memory _name) BaseTokenizedStrategy(_asset, _name) {
        //approvals:
        ERC20(_asset).safeApprove(curve, type(uint256).max);
        ERC20(LST).safeApprove(curve, type(uint256).max);

        maxSingleTrade = 1_000 * 1e18; //maximum amount that should be swapped in one go
        swapSlippage = 200; //actual slippage for a trade independent of the depeg; we check with chainlink for additional depeg
    }

    receive() external payable {} //able to receive ETH

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 _assetAmount) internal override {
        _stake(_assetAmount);
    }

    function _stake(uint256 _amount) internal {
        if(_amount == 0){
            return;
        }
        IWETH(asset).withdraw(_amount); //WETH --> ETH
        if(ICurve(curve).get_dy(ASSETID, LSTID, _amount) < _amount){ //check if we receive more than 1:1 through swaps
            ISTETH(LST).submit{value: _amount}(gov); //stake 1:1
        }else{
            ICurve(curve).exchange{value: _amount}(ASSETID, LSTID, _amount, _amount); //swap for at least 1:1
        }
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return maxSingleTrade;
    }

    function _freeFunds(uint256 _assetAmount) internal override {
        //Unstake LST amount proportional to the shares redeemed:
        uint256 LSTamountToUnstake = _balanceLST() * _assetAmount / TokenizedStrategy.totalAssets();
        _unstake(LSTamountToUnstake);
        uint256 assetBalance = _balanceAsset();
        if (assetBalance > _assetAmount) { //did we swap too much?
            _stake(assetBalance - _assetAmount); //in case we swapped too much to satisfy _assetAmount, swap rest back to LST
        }
    }

    function _unstake(uint256 _amount) internal {
        uint256 expectedAmountOut = _amount * (MAX_BPS - swapSlippage) / MAX_BPS; //Without oracle we expect 1:1, but can offset that expectation with swapSlippage
        if (address(chainlinkOracle) != address(0)){ //Check if chainlink oracle is set
            uint256 LSTprice = uint256(chainlinkOracle.latestAnswer()); //Account for decimals in chainlinkOracle
            if (LSTprice > 0) {
                expectedAmountOut = expectedAmountOut * LSTprice / WAD; //adjust expectedAmountOut by actual depeg
            }
        }
        ICurve(curve).exchange(LSTID, ASSETID, _amount, expectedAmountOut);
        IWETH(asset).deposit{value: address(this).balance}(); //ETH --> WETH
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        // deposit any loose balance
        uint256 balance = address(this).balance;
        if (balance > 0) {
            IWETH(asset).deposit{value: balance}();
        }
        // deposit any loose asset in the strategy
        uint256 looseAsset = _balanceAsset();
        if (looseAsset > 0 && !TokenizedStrategy.isShutdown()) {
            _stake(Math.min(maxSingleTrade, looseAsset));
        }
        // Total assets of the strategy:
        _totalAssets = _balanceAsset() + _balanceLST() * _getPessimisticLSTprice() / WAD; //use pessimistic price to make sure people cannot withdraw more than the current worth of the LST
    }

    function _getPessimisticLSTprice() internal view returns (uint256 LSTprice) {
        LSTprice = ICurve(curve).get_dy(LSTID, ASSETID, WAD); //price determined through actual swap route
        if (address(chainlinkOracle) != address(0)){ //Check if chainlink oracle is set
            uint256 chainlinkPrice = uint256(chainlinkOracle.latestAnswer());
            if (chainlinkPrice > 0) {
                LSTprice = Math.min(LSTprice, chainlinkPrice); //use pessimistic price to make sure people cannot withdraw more than the current worth of the LST
            }
        }
    }

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _balanceLST() internal view returns (uint256){
        return ERC20(LST).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the amount of asset the strategy holds.
    function balanceAsset() external view returns (uint256) {
        return _balanceAsset();
    }
    
    /// @notice Returns the amount of staked asset in liquid staking token (LST) the strategy holds.
    function balanceLST() external view returns (uint256) {
        return _balanceLST();
    }

    /// @notice Set the maximum amount of asset that can be withdrawn or can be moved by keepers in a single transaction. This is to avoid unnecessarily large slippages and incentivizes staggered withdrawals.
    function setMaxSingleTrade(uint256 _maxSingleTrade) external onlyManagement {
        maxSingleTrade = _maxSingleTrade;
    }

    /// @notice Set the maximum slippage in basis points (BPS) to accept when swapping asset <-> staked asset in liquid staking token (LST).
    function setSwapSlippage(uint256 _swapSlippage) external onlyManagement {
        require(_swapSlippage <= MAX_BPS);
        swapSlippage = _swapSlippage;
    }

    /*//////////////////////////////////////////////////////////////
                GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    modifier onlyGovernance() {
        require(msg.sender == gov, "!gov");
        _;
    }

    /// @notice Set the curve router address in case TVL has migrated to a new curve pool. Only callable by governance.
    function setCurveRouter(address _curve) external onlyGovernance {
        require(_curve != address(0));
        ERC20(asset).safeApprove(_curve, type(uint256).max);
        ERC20(LST).safeApprove(_curve, type(uint256).max);
        curve = _curve;
    }

    /// @notice Set the chainlink oracle address to a new address. Can be set to address(0) to circumvent chainlink pricing. Only callable by governance.
    function setChainlinkOracle(address _chainlinkOracle) external onlyGovernance {
        chainlinkOracle = AggregatorInterface(_chainlinkOracle);
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY:
    //////////////////////////////////////////////////////////////*/

    // Emergency withdraw LST amount and swap. Best to do this in steps.
    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = Math.min(_amount, _balanceLST());
        _unstake(_amount);
    }

    /// @notice Initiate a liquid staking token (LST) withdrawal process to redeem 1:1. Returns requestIds which can be used to claim asset into the strategy.
    /// @param _amounts the amounts of LST to initiate a withdrawal process for.
    function initiateLSTwithdrawal(uint256[] calldata _amounts) external onlyManagement returns (uint256[] memory requestIds) {
        ERC20(LST).safeApprove(withdrawalQueueLST, type(uint256).max);
        requestIds = IQueue(withdrawalQueueLST).requestWithdrawals(_amounts, address(this));
    }

    /// @notice Claim asset from a liquid staking token (LST) withdrawal process to redeem 1:1. Use the requestId from initiateLSTwithdrawal() as argument.
    /// @param _requestId return from calling initiateLSTwithdrawal() to identify the withdrawal.
    function claimLSTwithdrawal(uint256 _requestId) external onlyManagement {
        IQueue(withdrawalQueueLST).claimWithdrawal(_requestId);
    }
}

interface IQueue {
    function requestWithdrawals(uint256[] calldata _amounts, address _owner) external returns (uint256[] memory requestIds);
    function claimWithdrawal(uint256 _requestId) external;
}

