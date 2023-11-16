// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OperationTest is Setup {
    uint256 internal constant maxDivider = 100;
    
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

    function test_operation_NoFees(uint256 _amount) public {
        console.log("strategy.address", address(strategy));
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        setPerformanceFeeToZero(address(strategy));
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);
        // Earn Interest
        skip(10 days);

        // Report loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount, "!final balance");
    }

    function test_profitableReport_NoFees_Airdrop(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        setPerformanceFeeToZero(address(strategy));
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after first report", loss);
         

        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop", toAirdrop);
        airdrop(address(asset), address(strategy), toAirdrop);
        
        if (toAirdrop > highProfit) {
            vm.prank(management);
            strategy.setSwapSlippage(swapSlippageForHighProfit);
            console.log("setSwapSlippage"); 
            vm.prank(management);
            strategy.setLossLimitRatio(swapSlippageForHighProfit);
        }

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);

        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toAirdrop, "!profit");
        console.log("profit after second report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after second report", loss);
         

        console.log("TOTAL ASSETS after airdorp report", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
    
        skip(strategy.profitMaxUnlockTime());
        console.log("TOTAL ASSETS after unlocktime report", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);

        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount + toAirdrop, "!final balance");
        console.log("user balance at end", asset.balanceOf(user));
    }

    function test_profitableReport_NoFees_ProfitableInvestment(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount / 2);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        setPerformanceFeeToZero(address(strategy));
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);
        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after first report", loss);
         

        //profit simulation:
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop", toAirdrop);
        airdrop(LST, address(strategy), toAirdrop);        
        if (toAirdrop > highProfit) {
            vm.prank(management);
            strategy.setSwapSlippage(swapSlippageForHighProfit);
            console.log("setSwapSlippage"); 
            vm.prank(management);
            strategy.setLossLimitRatio(swapSlippageForHighProfit);
        }

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);

        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toAirdrop, "!profit");
        console.log("profit after second report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after second report", loss);
         

        console.log("TOTAL ASSETS after airdorp report", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
        skip(strategy.profitMaxUnlockTime());
        console.log("TOTAL ASSETS after unlocktime report", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);
        checkStrategyTotals(strategy, 0, 0, 0);
        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount + toAirdrop, "!final balance");
        console.log("user balance at end", asset.balanceOf(user));
    }

    function test_profitableReport_NoFees_ProfitableInvestment_MultipleUsers_FuzzedProfit(
        uint256 _amount,
        //uint16 _profitFactor,
        uint16 _divider
    ) public {
        vm.assume(_amount > minFuzzAmount * maxDivider && _amount < maxFuzzAmount /2);
        //_amount = bound(_amount, minFuzzAmount * maxDivider, maxFuzzAmount); 
        _divider = uint16(bound(uint256(_divider), 1, maxDivider));
        //_profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        //vm.assume(_divider > 0 && _divider < maxDivider);
        uint16 _profitFactor = uint16(maxDivider) / _divider;
        //vm.assume(_secondDivider > 0 && _secondDivider < maxDivider);       
        setPerformanceFeeToZero(address(strategy));
        address secondUser = address(22);
        address thirdUser = address(33);
        uint256 secondUserAmount = _amount / _divider;
        uint256 thirdUserAmount = _amount / (_divider * 2);
        uint256 profit;
        uint256 loss;
        uint256 redeemAmount;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        mintAndDepositIntoStrategy(strategy, secondUser, secondUserAmount);
        mintAndDepositIntoStrategy(strategy, thirdUser, thirdUserAmount);
        checkStrategyTotals(strategy, _amount + secondUserAmount + thirdUserAmount, 0, _amount + secondUserAmount + thirdUserAmount);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after first report", loss);
         

        //profit simulation:
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop", toAirdrop);
        airdrop(LST, address(strategy), toAirdrop);        
        if (toAirdrop > highProfit) {
            vm.prank(management);
            strategy.setSwapSlippage(swapSlippageForHighProfit);
            console.log("setSwapSlippage"); 
            vm.prank(management);
            strategy.setLossLimitRatio(swapSlippageForHighProfit);
        }

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);

        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toAirdrop, "!profit");
        console.log("profit after second report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after second report", loss);
         

        console.log("TOTAL ASSETS after airdorp report", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
         
         
         
        skip(strategy.profitMaxUnlockTime());
        console.log("TOTAL ASSETS after unlocktime report", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
         
         
         

        // Withdraw part of funds user
        //uint256 balanceBefore = asset.balanceOf(user) + asset.balanceOf(secondUser) + asset.balanceOf(thirdUser);
        redeemAmount = strategy.balanceOf(user) / 8;
        vm.prank(user);
        strategy.redeem(redeemAmount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Withdraw part of funds secondUser
        redeemAmount = strategy.balanceOf(secondUser) / 6;
        vm.prank(secondUser);
        strategy.redeem(redeemAmount, secondUser, secondUser);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Withdraw part of funds thirdUser
        redeemAmount = strategy.balanceOf(thirdUser) / 4;
        vm.prank(thirdUser);
        strategy.redeem(redeemAmount, thirdUser, thirdUser);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        skip(strategy.profitMaxUnlockTime());

        // Withdraw all funds
        

        // withdraw all funds
        console.log("user shares: ", strategy.balanceOf(user));
        console.log("user2 shares: ", strategy.balanceOf(secondUser));
        console.log("user3 shares: ", strategy.balanceOf(thirdUser));
        redeemAmount = strategy.balanceOf(user);
        if (redeemAmount > 0){
            vm.prank(user);
            strategy.redeem(redeemAmount, user, user);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        redeemAmount = strategy.balanceOf(secondUser);
        if (redeemAmount > 0){
            vm.prank(secondUser);
            strategy.redeem(redeemAmount, secondUser, secondUser);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        redeemAmount = strategy.balanceOf(thirdUser);
        if (redeemAmount > 0){
            vm.prank(thirdUser);
            strategy.redeem(redeemAmount, thirdUser, thirdUser);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        // verify users earned profit
        assertGe(asset.balanceOf(user)* (MAX_BPS + expectedActivityLossMultipleUsersBPS)/MAX_BPS, _amount, "!final balance");
        assertGe(asset.balanceOf(secondUser)* (MAX_BPS + expectedActivityLossMultipleUsersBPS)/MAX_BPS, secondUserAmount, "!final balance");
        assertGe(asset.balanceOf(thirdUser)* (MAX_BPS + expectedActivityLossMultipleUsersBPS)/MAX_BPS, thirdUserAmount, "!final balance");

        //total gain:
        //assertGe((asset.balanceOf(user)+asset.balanceOf(secondUser)+asset.balanceOf(thirdUser)) * (MAX_BPS + expectedActivityLossMultipleUsersBPS)/MAX_BPS, balanceBefore + _amount + secondUserAmount + thirdUserAmount + toAirdrop, "!final balance");
        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_profitableReport_NoFees_ProfitableInvestment_MultipleUsers_FixedProfit(
        uint256 _amount,
        uint16 _divider
        //,uint16 _secondDivider
    ) public {
        vm.assume(_amount > minFuzzAmount * maxDivider && _amount < maxFuzzAmount / 2);
        //_amount = bound(_amount, minFuzzAmount * maxDivider, maxFuzzAmount); 
        _divider = uint16(bound(uint256(_divider), 1, maxDivider));
        //vm.assume(_amount > minFuzzAmount * maxDivider && _amount < maxFuzzAmount);
        //_profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        uint16 _profitFactor = 2_00; //2% profit
        //vm.assume(_divider > 0 && _divider < maxDivider);
        //vm.assume(_secondDivider > 0 && _secondDivider < maxDivider);
        
        setPerformanceFeeToZero(address(strategy));
        
        address secondUser = address(22);
        address thirdUser = address(33);
        uint256 secondUserAmount = _amount / _divider;
        //uint256 thirdUserAmount = _amount / _secondDivider;
        uint256 thirdUserAmount = _amount / (_divider * 10);
        uint256 profit;
        uint256 loss;
        uint256 redeemAmount;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        mintAndDepositIntoStrategy(strategy, secondUser, secondUserAmount);
        mintAndDepositIntoStrategy(strategy, thirdUser, thirdUserAmount);
        checkStrategyTotals(strategy, _amount + secondUserAmount + thirdUserAmount, 0, _amount + secondUserAmount + thirdUserAmount);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after first report", loss);
         

        //profit simulation:
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop", toAirdrop);
        airdrop(LST, address(strategy), toAirdrop);        
        if (toAirdrop > highProfit) {
            vm.prank(management);
            strategy.setSwapSlippage(swapSlippageForHighProfit);
            console.log("setSwapSlippage"); 
            vm.prank(management);
            strategy.setLossLimitRatio(swapSlippageForHighProfit);
        }

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);

        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toAirdrop, "!profit");
        console.log("profit after second report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after second report", loss);
         

        skip(strategy.profitMaxUnlockTime());

        // Withdraw part of funds user
        //uint256 balanceBefore = asset.balanceOf(user) + asset.balanceOf(secondUser) + asset.balanceOf(thirdUser);
        redeemAmount = strategy.balanceOf(user) / 8;
        vm.prank(user);
        strategy.redeem(redeemAmount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Withdraw part of funds secondUser
        redeemAmount = strategy.balanceOf(secondUser) / 6;
        vm.prank(secondUser);
        strategy.redeem(redeemAmount, secondUser, secondUser);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Withdraw part of funds thirdUser
        redeemAmount = strategy.balanceOf(thirdUser) / 4;
        vm.prank(thirdUser);
        strategy.redeem(redeemAmount, thirdUser, thirdUser);
        checkStrategyInvariantsAfterRedeem(strategy);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        skip(strategy.profitMaxUnlockTime());

        // withdraw all funds
        console.log("user shares: ", strategy.balanceOf(user));
        console.log("user2 shares: ", strategy.balanceOf(secondUser));
        console.log("user3 shares: ", strategy.balanceOf(thirdUser));
        redeemAmount = strategy.balanceOf(user);
        if (redeemAmount > 0){
            vm.prank(user);
            strategy.redeem(redeemAmount, user, user);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        redeemAmount = strategy.balanceOf(secondUser);
        if (redeemAmount > 0){
            vm.prank(secondUser);
            strategy.redeem(redeemAmount, secondUser, secondUser);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        redeemAmount = strategy.balanceOf(thirdUser);
        if (redeemAmount > 0){
            vm.prank(thirdUser);
            strategy.redeem(redeemAmount, thirdUser, thirdUser);
            checkStrategyInvariantsAfterRedeem(strategy);
        }
        // verify users earned profit
        assertGe(asset.balanceOf(user)* (MAX_BPS + expectedActivityLossMultipleUsersBPS)/MAX_BPS, _amount, "!final balance");
        assertGe(asset.balanceOf(secondUser)* (MAX_BPS + expectedActivityLossMultipleUsersBPS)/MAX_BPS, secondUserAmount, "!final balance");
        assertGe(asset.balanceOf(thirdUser)* (MAX_BPS + expectedActivityLossMultipleUsersBPS)/MAX_BPS, thirdUserAmount, "!final balance");

        //total gain:
        //assertGe((asset.balanceOf(user)+asset.balanceOf(secondUser)+asset.balanceOf(thirdUser)) * (MAX_BPS + expectedActivityLossMultipleUsersBPS)/MAX_BPS, balanceBefore + _amount + secondUserAmount + thirdUserAmount + toAirdrop, "!final balance");
        checkStrategyTotals(strategy, 0, 0, 0);
    }

    function test_profitableReport_withFees_Airdrop(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount/2);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        uint256 profit;
        uint256 loss;
        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);
        console.log("performance fees: ", strategy.performanceFee());

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("initialLoss after first report", loss);

        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop", toAirdrop);
        airdrop(address(asset), address(strategy), toAirdrop);
        if (toAirdrop > highProfit) {
            vm.prank(management);
            strategy.setSwapSlippage(swapSlippageForHighProfit);
            console.log("setSwapSlippage"); 
            vm.prank(management);
            strategy.setLossLimitRatio(swapSlippageForHighProfit);
        }

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        console.log("after profit report: actualShares of performanceFeeRecipient", strategy.balanceOf(performanceFeeRecipient));

        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toAirdrop, "!profit");
        console.log("profit after second report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after second report", loss);

        console.log("TOTAL ASSETS after airdorp report", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
         
        skip(strategy.profitMaxUnlockTime());
        console.log("TOTAL ASSETS after maxunlocktime", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
         
        // Get the expected fee
        uint256 actualShares = strategy.balanceOf(performanceFeeRecipient);
        console.log("actualShares of performanceFeeRecipient", actualShares);
        console.log("shares of user", strategy.balanceOf(user));
        console.log("total Shares", strategy.totalSupply());
        assertEq(strategy.balanceOf(performanceFeeRecipient), actualShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);

        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount, "!final balance");
        console.log("user balance at end", asset.balanceOf(user));
        
        if (actualShares > 0){
            vm.prank(performanceFeeRecipient);
            strategy.redeem(actualShares, performanceFeeRecipient, performanceFeeRecipient);
            checkStrategyInvariantsAfterRedeem(strategy);
        }

        assertGe(asset.balanceOf(performanceFeeRecipient) * (MAX_BPS + 500)/MAX_BPS, actualShares, "!perf fee out");
        console.log("strategist balance at end", asset.balanceOf(user));
    }

    function test_profitableReport_withFees_ProfitableInvestment(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        uint256 profit;
        uint256 loss;
        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);
        console.log("performance fees: ", strategy.performanceFee());

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("initialLoss after first report", loss);

        //profit simulation:
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop", toAirdrop);
        airdrop(LST, address(strategy), toAirdrop);        
        if (toAirdrop > highProfit) {
            vm.prank(management);
            strategy.setSwapSlippage(swapSlippageForHighProfit);
            console.log("setSwapSlippage"); 
            vm.prank(management);
            strategy.setLossLimitRatio(swapSlippageForHighProfit);
        }

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        console.log("after profit report: actualShares of performanceFeeRecipient", strategy.balanceOf(performanceFeeRecipient));

        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toAirdrop, "!profit");
        console.log("profit after second report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after second report", loss);

        console.log("TOTAL ASSETS after airdorp report", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
         
        skip(strategy.profitMaxUnlockTime());
        console.log("TOTAL ASSETS after maxunlocktime", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
         
        // Get the expected fee
        uint256 actualShares = strategy.balanceOf(performanceFeeRecipient);
        console.log("actualShares of performanceFeeRecipient", actualShares);
        console.log("shares of user", strategy.balanceOf(user));
        console.log("total Shares", strategy.totalSupply());
        assertEq(strategy.balanceOf(performanceFeeRecipient), actualShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);

        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount, "!final balance");
        console.log("user balance at end", asset.balanceOf(user));
        
        if (actualShares > 0){
            vm.prank(performanceFeeRecipient);
            strategy.redeem(actualShares, performanceFeeRecipient, performanceFeeRecipient);
            checkStrategyInvariantsAfterRedeem(strategy);
        }

        assertGe(asset.balanceOf(performanceFeeRecipient) * (MAX_BPS + 500)/MAX_BPS, actualShares, "!perf fee out");
        console.log("strategist balance at end", asset.balanceOf(user));
    }

    function test_profitableReport_withFees_ProfitableInvestment_with_extra_report(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        uint256 profit;
        uint256 loss;
        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);
        console.log("performance fees: ", strategy.performanceFee());

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, 0, _amount);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("initialLoss after first report", loss);

        //profit simulation:
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        console.log("toAirdrop", toAirdrop);
        airdrop(LST, address(strategy), toAirdrop);        
        if (toAirdrop > highProfit) {
            vm.prank(management);
            strategy.setSwapSlippage(swapSlippageForHighProfit);
            console.log("setSwapSlippage"); 
            vm.prank(management);
            strategy.setLossLimitRatio(swapSlippageForHighProfit);
        }

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        console.log("after profit report: actualShares of performanceFeeRecipient", strategy.balanceOf(performanceFeeRecipient));
        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toAirdrop, "!profit");
        console.log("profit after second report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after second report", loss);

        console.log("TOTAL ASSETS after airdorp report", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
         
        skip(strategy.profitMaxUnlockTime());
        console.log("TOTAL ASSETS after maxunlocktime", strategy.totalAssets());
        console.log("balanceLST", strategy.balanceLST());
         
        // Get the expected fee
        uint256 actualShares = strategy.balanceOf(performanceFeeRecipient);
        console.log("actualShares of performanceFeeRecipient", actualShares);
        console.log("shares of user", strategy.balanceOf(user));
        console.log("total Shares", strategy.totalSupply());
        assertEq(strategy.balanceOf(performanceFeeRecipient), actualShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyInvariantsAfterRedeem(strategy);
        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount, "!final balance");
        console.log("user balance at end", asset.balanceOf(user));
        
        // Report profit third report
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after third report", loss);
        actualShares = strategy.balanceOf(performanceFeeRecipient);
        console.log("TOTAL ASSETS after third report", strategy.totalAssets());
         console.log("balanceLST", strategy.balanceLST());

        // Report profit fourth report
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        checkStrategyInvariantsAfterReport(strategy);
        // Check return Values
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after fourth report", loss);
        actualShares = strategy.balanceOf(performanceFeeRecipient);

        console.log("TOTAL ASSETS after fourth report", strategy.totalAssets());
         console.log("balanceLST", strategy.balanceLST());

        skip(strategy.profitMaxUnlockTime());
        console.log("TOTAL ASSETS after unlocking fourth report", strategy.totalAssets());
         console.log("balanceLST", strategy.balanceLST());

        if (actualShares > 0){
            vm.prank(performanceFeeRecipient);
            strategy.redeem(actualShares, performanceFeeRecipient, performanceFeeRecipient);
            checkStrategyInvariantsAfterRedeem(strategy);
        }

        assertGe(asset.balanceOf(performanceFeeRecipient) * (MAX_BPS + 500)/MAX_BPS, actualShares, "!perf fee out");
        console.log("strategist balance at end", asset.balanceOf(performanceFeeRecipient));
    }
}
