// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import "forge-std/console.sol";
import {ExtendedTest} from "./ExtendedTest.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/Lido/ISTETH.sol";
import "../../interfaces/Lido/IWETH.sol";

import {Strategy} from "../../Strategy.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";

// Inherit the events so they can be checked if desired.
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol"; 
import {TokenizedStrategy} from "@tokenized-strategy/TokenizedStrategy.sol";

interface IFactory {
    function governance() external view returns (address);

    function set_protocol_fee_bps(uint16) external;

    function set_protocol_fee_recipient(address) external;
}

contract Setup is ExtendedTest, IEvents {
    // Contract instancees that we will use repeatedly.
    ERC20 public asset;
    IStrategyInterface public strategy;

    mapping(string => address) public tokenAddrs;

    // Addresses for different roles we will use repeatedly.
    address public user = address(10);
    address public user2 = address(5);
    address public user3 = address(6);
    address public user4 = address(7);
    address payable public bucket = payable(0xa840CaD8DbF5504F800Fc6aA4582d841895169E7);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public LST;

    // Address of the real deployed Factory
    address public factory = 0x85E2861b3b1a70c90D28DfEc30CE6E07550d83e9;

    // Integer variables that will be used repeatedly.
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    // Fuzz
    uint256 public maxFuzzAmount = 1e4 * 1e18;
    uint256 public minFuzzAmount = 1e15;

    uint256 public expectedActivityLossBPS = 100;
    uint256 public expectedActivityLossMultipleUsersBPS = 100;
    uint256 public expectedProfitReductionBPS = 100;
    uint256 public ONE_ASSET;
    uint256 public highProfit;
    uint256 public highLoss;
    uint256 public swapSlippageForHighProfit;
    uint256 public swapSlippageForHighLoss;

    bytes32 public constant BASE_STRATEGY_STORAGE = bytes32(uint256(keccak256("yearn.base.strategy.storage")) - 1);

    // Default prfot max unlock time is set for 10 days
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        uint256 mainnetFork = vm.createFork("mainnet");
        uint256 polygonFork = vm.createFork("polygon");
        //uint256 avaxFork = vm.createFork("avax");
        //uint256 optimismFork = vm.createFork("optimism");
        //uint256 arbitrumFork = vm.createFork("arbitrum");

        vm.selectFork(mainnetFork);
        //vm.selectFork(polygonFork);
        //vm.selectFork(avaxFork);
        //vm.selectFork(optimismFork);
        //vm.selectFork(arbitrumFork);

        //Fork specific parameters:
        //MAINNET:
        if(vm.activeFork() == mainnetFork) {
            asset = ERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); //WETH
            ONE_ASSET = 1e18;
            highProfit = 900e18;
            highLoss = 900e18;
            swapSlippageForHighProfit = 2_00;
            swapSlippageForHighLoss = 2_00;
        }
        //Polygon:
        if(vm.activeFork() == polygonFork) {
            asset = ERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619); //WETH
            //asset = ERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270); //WMATIC
        }

        // Set decimals
        decimals = asset.decimals();

        // Deploy strategy and set variables
        strategy = IStrategyInterface(setUpStrategy());

        // label all the used addresses for traces
        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "asset");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");

        vm.prank(management);
        strategy.setMaxSingleTrade(100e6*ONE_ASSET);
        vm.prank(management);
        strategy.setChainlinkHeartbeat(type(uint256).max); //block.timestamp in tests advances with days skipped while the chainlink updatedAt will not, so we need to ignore this in tests. There are additional tests for this specifically in Shutdown.t.sol.
        LST = strategy.LST();
    }

    function setUpStrategy() public returns (address) {
        // we save the strategy as a IStrategyInterface to give it the needed interface
        IStrategyInterface _strategy = IStrategyInterface(
            address(new Strategy(address(asset), "Tokenized Strategy"))
        );

        // set keeper
        _strategy.setKeeper(keeper);
        // set treasury
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        // set management of the strategy
        _strategy.setPendingManagement(management);
        // Accept mangagement.
        vm.prank(management);
        _strategy.acceptManagement();

        return address(_strategy);
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        airdrop(address(asset), _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    // For checking the amounts in the strategy
    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public {
        assertEq(_strategy.totalAssets(), _totalAssets, "!totalAssets");
        assertEq(_strategy.totalDebt(), _totalDebt, "!totalDebt");
        assertEq(_strategy.totalIdle(), _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(address _asset, address _to, uint256 _amount) public {
        if (_asset == LST) {
            console.log("LST mode");
            uint256 assetBalanceBefore = asset.balanceOf(bucket);
            console.log("assetBalanceBefore", assetBalanceBefore);
            deal(address(asset), bucket, assetBalanceBefore + _amount); //asset in bucket
            console.log("wethBalance Now", asset.balanceOf(bucket));
            vm.prank(bucket);

            IWETH(address(asset)).withdraw(_amount); //WETH --> ETH
            console.log("ethBalance Now", bucket.balance);
            ISTETH(LST).submit{value: _amount}(bucket); //stake
            console.log("LST Now bucket", ERC20(LST).balanceOf(bucket));
            console.log("LST Now stratregy", ERC20(LST).balanceOf(_to));
            ERC20(LST).transfer(_to, _amount); //transfer LST to _to address
            console.log("LST Now bucket", ERC20(LST).balanceOf(bucket));
            console.log("LST Now stratregy", ERC20(LST).balanceOf(_to));
            assertGe(ERC20(LST).balanceOf(_to), _amount, "LST never arrived");
            return;
        }
        uint256 balanceBefore = ERC20(_asset).balanceOf(_to);
        deal(_asset, _to, balanceBefore + _amount);
    }

    function checkStrategyInvariantsAfterReport(IStrategyInterface _strategy) public {
        if (!_strategy.isShutdown()) {
            assertLe(_strategy.balanceAsset(), 1, "!inv after report: balanceAsset == 0");
        }
        assertLe(address(_strategy).balance, 1, "!inv after report: balance == 0");
    }

    function checkStrategyInvariantsAfterRedeem(IStrategyInterface _strategy) public {
        if (!_strategy.isShutdown()) {
            assertLe(_strategy.balanceAsset(), 1e18, "!inv after redeem: balanceAsset == 0");
        }
        assertLe(address(_strategy).balance, 2, "!inv after redeem: balance == 0");
    }

    function getExpectedProtocolFee(
        uint256 _amount,
        uint16 _fee
    ) public view returns (uint256) {
        uint256 timePassed = block.timestamp - strategy.lastReport();

        return (_amount * _fee * timePassed) / MAX_BPS / 31_556_952;
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        // Need to make sure there is a protocol fee recipient to set the fee.
        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    // For easier calculations we may want to set the performance fee
    // to 0 in some tests which is underneath the minimum. So we do it manually.
    function setPerformanceFeeToZero(address _strategy) public {
        bytes32 slot;
        TokenizedStrategy.StrategyData storage S = _strategyStorage();

        assembly {
            // Perf fee is stored in the 12th slot of the Struct.
            slot := add(S.slot, 12)
        }

        // Performance fee is packed in a slot with other variables so we need
        // to maintain the same variables packed in the slot

        // profitMaxUnlock time is a uint32 at the most significant spot.
        bytes32 data = bytes4(
            uint32(IStrategyInterface(_strategy).profitMaxUnlockTime())
        );
        // Free up space for the uint16 of performancFee
        data = data >> 16;
        // Store 0 in the performance fee spot.
        data |= bytes2(0);
        // Shit 160 bits for an address
        data = data >> 160;
        // Store the strategies peformance fee recipient
        data |= bytes20(
            uint160(IStrategyInterface(_strategy).performanceFeeRecipient())
        );
        // Shift the remainder of padding.
        data = data >> 48;

        // Manually set the storage slot that holds the perfomance fee to 0
        vm.store(_strategy, slot, data);
    }

    function _strategyStorage()
        internal
        pure
        returns (TokenizedStrategy.StrategyData storage S)
    {
        // Since STORAGE_SLOT is a constant, we have to put a variable
        // on the stack to access it from an inline assembly block.
        bytes32 slot = BASE_STRATEGY_STORAGE;
        assembly {
            S.slot := slot
        }
    }
}
