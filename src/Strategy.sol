// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import {BaseHealthCheck} from "@periphery/HealthCheck/BaseHealthCheck.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IBalancer, IBalancerPool} from "./interfaces/Balancer/IBalancer.sol";
import "./interfaces/Chainlink/AggregatorInterface.sol";

/// @title yearn-v3-LST-POLYGON-WSTETH
/// @author mil0x
/// @notice yearn-v3 Strategy that stakes asset into Liquid Staking Token (LST).
contract Strategy is BaseHealthCheck {
    using SafeERC20 for ERC20;
    address internal constant LST = 0x03b54A6e9a984069379fae1a4fC4dBAE93B3bCCD; //WSTETH
    // Use chainlink oracle to check latest WSTETH/ETH price
    AggregatorInterface public chainlinkOracle = AggregatorInterface(0x10f964234cae09cB6a9854B56FF7D4F38Cda5E6a); //WSTETH/ETH
    uint256 public chainlinkHeartbeat = 86400;
    address internal constant BALANCER = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public pool = 0x65Fe9314bE50890Fb01457be076fAFD05Ff32B9A; //wsteth weth pool

    // Parameters    
    uint256 public maxSingleTrade; //maximum amount that should be swapped by the keeper in one go
    uint256 public maxSingleWithdraw; //maximum amount that should be withdrawn in one go
    uint256 public swapSlippage; //actual slippage for a trade including peg
    uint256 public profitSlippage; //pessimistic correction to the profit to simulate having to realize the profit to asset

    uint256 internal constant WAD = 1e18;
    uint256 internal constant ASSET_DUST = 1000;
    address internal constant GOV = 0xC4ad0000E223E398DC329235e6C497Db5470B626; //yearn governance on polygon

    constructor(address _asset, string memory _name) BaseHealthCheck(_asset, _name) {
        //approvals:
        ERC20(_asset).safeApprove(BALANCER, type(uint256).max);
        ERC20(LST).safeApprove(BALANCER, type(uint256).max);

        maxSingleTrade = 51 * 1e18; //maximum amount that should be swapped by the keeper in one go
        maxSingleWithdraw = 51 * 1e18; //maximum amount that should be withdrawn in one go
        swapSlippage = 5_00; //actual maximum allowed slippage for a trade
        profitSlippage = 50; //pessimistic correction to the profit to simulate having to realize the profit to asset

        _setLossLimitRatio(5_00); // 5% acceptable loss in a report before we revert. Use the external setLossLimitRatio() function to change the value/circumvent this.
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _deployFunds(uint256 /*_amount*/) internal override {
        //do nothing, we want to only have the keeper swap funds
    }

    function _LSTprice() internal view returns (uint256 LSTprice) {
        (, int256 answer, , uint256 updatedAt, ) = chainlinkOracle.latestRoundData();
        LSTprice = uint256(answer);
        require((LSTprice > 1 && block.timestamp - updatedAt < chainlinkHeartbeat), "!chainlink");
    }

    function _stake(uint256 _amount) internal {
        if (_amount < ASSET_DUST) {
            return;
        }
        swapBalancer(address(asset), LST, _amount, _amount * WAD / _LSTprice() * (MAX_BPS - swapSlippage) / MAX_BPS); //adjust minAmountOut by actual price & account for slippage of the swap
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return TokenizedStrategy.totalIdle() + maxSingleWithdraw;
    }
    
    function _freeFunds(uint256 _assetAmount) internal override {
        //Unstake LST amount proportional to the shares redeemed:
        uint256 LSTamountToUnstake = _balanceLST() * _assetAmount / TokenizedStrategy.totalDebt();
        if (LSTamountToUnstake > 2) {
            _unstake(LSTamountToUnstake);
        }
    }

    function _unstake(uint256 _amount) internal {
        swapBalancer(LST, address(asset), _amount, _amount * _LSTprice() / WAD * (MAX_BPS - swapSlippage) / MAX_BPS); //adjust minAmountOut by actual price & account for slippage of the swap
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        uint256 oldTotalAssets = TokenizedStrategy.totalAssets();
        // invest any loose asset
        if (!TokenizedStrategy.isShutdown()) {
            _stake(Math.min(maxSingleTrade, _balanceAsset()));
        }
        // new total assets of the strategy:
        uint256 newTotalAssets = _balanceAsset() + _balanceLST() * _LSTprice() / WAD;
        // check if there was a profit:
        if (newTotalAssets > oldTotalAssets) {
            uint256 profit = newTotalAssets - oldTotalAssets;
            // scenario with profit, pessimistically account for profit at a value as if it had been swapped back to asset with a swap slippage
            _totalAssets = oldTotalAssets + profit * (MAX_BPS - profitSlippage) / MAX_BPS;
        } else {
            // scenario with no profit, simply report total assets
            _totalAssets = newTotalAssets;
        }
    }

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _balanceLST() internal view returns (uint256){
        return ERC20(LST).balanceOf(address(this));
    }

    function swapBalancer(address _tokenIn, address _tokenOut, uint256 _amount, uint256 _minAmountOut) internal {
        IBalancer.SingleSwap memory singleSwap;
        singleSwap.poolId = IBalancerPool(pool).getPoolId();
        singleSwap.kind = 0;
        singleSwap.assetIn = _tokenIn;
        singleSwap.assetOut = _tokenOut;
        singleSwap.amount = _amount;
        IBalancer.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = true;
        funds.recipient = payable(this);
        funds.toInternalBalance = false;
        IBalancer(BALANCER).swap(singleSwap, funds, _minAmountOut, block.timestamp);
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

    /// @notice Set the maximum amount of asset that can be moved by keepers in a single transaction. This is to avoid unnecessarily large slippages when harvesting.
    function setMaxSingleTrade(uint256 _maxSingleTrade) external onlyManagement {
        maxSingleTrade = _maxSingleTrade;
    }

    /// @notice Set the maximum amount of asset that can be withdrawn in a single transaction. This is to avoid unnecessarily large slippages and incentivizes staggered withdrawals.
    function setMaxSingleWithdraw(uint256 _maxSingleWithdraw) external onlyManagement {
        maxSingleWithdraw = _maxSingleWithdraw;
    }

    /// @notice Set the maximum slippage in basis points (BPS) to accept when swapping asset <-> staked asset in liquid staking token (LST).
    function setSwapSlippage(uint256 _swapSlippage) external onlyManagement {
        require(_swapSlippage <= MAX_BPS);
        swapSlippage = _swapSlippage;
    }

    /// @notice Set the profit slippage in basis points (BPS) to pessimistically correct the profit to reflect having to eventually swap it back to asset.
    function setProfitSlippage(uint256 _profitSlippage) external onlyManagement {
        require(_profitSlippage <= MAX_BPS);
        profitSlippage = _profitSlippage;
    }

    /// @notice Set Chainlink heartbeat to determine what qualifies as stale data in units of seconds. 
    function setChainlinkHeartbeat(uint256 _chainlinkHeartbeat) external onlyManagement {
        chainlinkHeartbeat = _chainlinkHeartbeat;
    }

    /*//////////////////////////////////////////////////////////////
                GOVERNANCE:
    //////////////////////////////////////////////////////////////*/

    modifier onlyGovernance() {
        require(msg.sender == GOV, "!gov");
        _;
    }

    /// @notice Set the balancer pool address in case TVL has migrated to a new balancer pool. Only callable by governance.
    function setPool(address _pool) external onlyGovernance {
        require(_pool != address(0));
        pool = _pool;
    }

    /// @notice Set the chainlink oracle address to a new address. Only callable by governance.
    function setChainlinkOracle(address _chainlinkOracle) external onlyGovernance {
        require(_chainlinkOracle != address(0));
        chainlinkOracle = AggregatorInterface(_chainlinkOracle);
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY:
    //////////////////////////////////////////////////////////////*/

    // Emergency swap LST amount. Best to do this in steps. This can fail if there is more slippage than swapSlippage, which can be updated with setSwapSlippage if needed.
    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = Math.min(_amount, _balanceLST());
        _unstake(_amount);
    }
}
