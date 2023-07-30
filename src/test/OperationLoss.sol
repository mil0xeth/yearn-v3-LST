// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OperationLossTest is Setup {
    uint256 internal constant maxDivider = 100;
    uint256 internal constant maxLossBPS = 50_00;
    uint256 internal constant maxLossPoolBPS = 30_00;
    
    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
    }

    function test_unprofitableReport_NoFees_LSTLoss(
        uint256 _amount,
        uint16 _lossFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, maxLossBPS));
        setPerformanceFeeToZero(address(strategy));
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after first report", loss);
        assertLe(address(strategy).balance, 100000000000000000);

        //throw away LST to simulate loss
        uint256 toThrow = (strategy.balanceLST() * _lossFactor) / MAX_BPS;
        console.log("toThrow", toThrow);
        vm.prank(address(strategy));
        ERC20(LST).transfer(bucket, toThrow);
        
        if (toThrow > highLoss) {
            vm.prank(management);
            strategy.setSwapSlippage(swapSlippageForHighProfit);
            console.log("setSwapSlippage"); 
        }

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(loss * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toThrow, "!loss");
        uint256 balanceBefore = asset.balanceOf(user);
        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);
        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS*2)/MAX_BPS, balanceBefore + _amount - toThrow, "!final balance");
        console.log("user balance at end", asset.balanceOf(user));
    }

    function test_unprofitableReport_NoFees_LSTLoss_Return(
        uint256 _amount,
        uint16 _lossFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 10, maxLossBPS));
        setPerformanceFeeToZero(address(strategy));
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after first report", loss);
        assertLe(address(strategy).balance, 100000000000000000);

        //throw away LST to simulate loss
        uint256 toThrow = (strategy.balanceLST() * _lossFactor) / MAX_BPS;
        console.log("toThrow", toThrow);
        vm.prank(address(strategy));
        ERC20(LST).transfer(bucket, toThrow);
        
        if (toThrow > highLoss) {
            vm.prank(management);
            strategy.setSwapSlippage(swapSlippageForHighProfit);
            console.log("setSwapSlippage"); 
        }

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(loss * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toThrow, "!loss");

        // Return
        uint256 toReturn = ERC20(LST).balanceOf(bucket);
        console.log("toReturn", toReturn);
        vm.prank(bucket);
        ERC20(LST).transfer(address(strategy), toReturn);

        // Report return as profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toThrow, "!profit");
        console.log("profit after final report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after final report", loss);
         assertLe(address(strategy).balance, 100000000000000000);
        console.log("TOTAL ASSETS after airdorp report", strategy.totalAssets());
        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);
        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);
        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount, "!final balance");
        console.log("user balance at end", asset.balanceOf(user));
    }

    function test_unprofitableReport_NoFees_InvestmentLoss(
        uint256 _amount,
        uint16 _lossFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 200, maxLossPoolBPS));
        setPerformanceFeeToZero(address(strategy));
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);
        vm.prank(management);
        strategy.setSwapSlippage(swapSlippageForHighLossPool);
        console.log("setSwapSlippage");

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after first report", loss);
        assertLe(address(strategy).balance, 100000000000000000);

        //throw away LST in pool pool to simulate LST price deterioration
        uint256 toThrow = (ERC20(LST).balanceOf(strategy.pool()) * _lossFactor) / MAX_BPS;
 	    console.log("toThrow", toThrow);
        address pool = strategy.pool();
        vm.prank(pool);
        ERC20(LST).transfer(bucket, toThrow);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        skip(strategy.profitMaxUnlockTime());
        // Check return Values
        //assertGe(loss * (MAX_BPS + expectedProfitReductionBPS*2)/MAX_BPS, toThrow, "!loss");

        //uint256 balanceBefore = asset.balanceOf(user);
        // Withdraw all funds
        vm.prank(user);
        console.log("redeem", _amount);
        strategy.redeem(_amount, user, user);
        console.log("after redeem", _amount);
        checkStrategyInvariantsAfterRedeem(strategy);
        checkStrategyTotals(strategy, 0, 0, 0);
        console.log("balanceAsset", strategy.balanceAsset());
        console.log("balanceLST", strategy.balanceLST());
        console.log("balance", address(strategy).balance);
        //assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount - toThrow, "!final balance");
        console.log("user balance at end", asset.balanceOf(user));
    }

    function test_unprofitableReport_NoFees_InvestmentLoss_Return(
        uint256 _amount,
        uint16 _lossFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _lossFactor = uint16(bound(uint256(_lossFactor), 50, maxLossPoolBPS));
        setPerformanceFeeToZero(address(strategy));
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);
        vm.prank(management);
        strategy.setSwapSlippage(swapSlippageForHighLossPool);
        console.log("setSwapSlippage");

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after first report", loss);
        assertLe(address(strategy).balance, 100000000000000000);

        //throw away LST in pool pool to simulate LST price deterioration
        uint256 toThrow = (ERC20(LST).balanceOf(strategy.pool()) * _lossFactor) / MAX_BPS;
 	    console.log("toThrow", toThrow);
        address pool = strategy.pool();
        vm.prank(pool);
        ERC20(LST).transfer(bucket, toThrow);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        //assertGe(loss * (MAX_BPS + expectedProfitReductionBPS*2)/MAX_BPS, toThrow, "!loss");

        // Return
        uint256 toReturn = ERC20(LST).balanceOf(bucket);
        console.log("toReturn", toReturn);
        vm.prank(bucket);
        ERC20(LST).transfer(pool, toReturn);

        // Report return as profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        //assertGe(profit * (MAX_BPS + expectedProfitReductionBPS*2)/MAX_BPS, toThrow, "!profit");
        console.log("profit after final report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after final report", loss);
        assertLe(address(strategy).balance, 100000000000000000);
        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);
        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);
        checkStrategyTotals(strategy, 0, 0, 0);
        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount, "!final balance");
        console.log("user balance at end", asset.balanceOf(user));
    }
}
