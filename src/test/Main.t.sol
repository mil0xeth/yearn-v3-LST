// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

import "../interfaces/maker/IMaker.sol";

contract MainTest is Setup {

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
        // TODO: add additional check on strat params
    }

    function test_main() public {
        //init
        uint256 _amount = 100e18;
        uint256 profit;
        uint256 loss;
        console.log("asset: ", asset.symbol());
        console.log("amount:", _amount );
        //user funds:
        airdrop(address(asset), user, _amount);
        assertEq(asset.balanceOf(user), _amount, "!totalAssets");
        //user deposit:
        depositIntoStrategy(strategy, user, _amount);
        assertEq(asset.balanceOf(user), 0, "user balance after deposit =! 0");
        assertEq(strategy.totalAssets(), _amount, "strategy.totalAssets() != _amount after deposit");
        console.log("strategy.totalAssets() after deposit: ", strategy.totalAssets() );
        console.log("strategy.balanceAsset() after deposit", strategy.balanceAsset());
        console.log("strategy.balanceLST()", strategy.balanceLST());

        // Earn Interest
        skip(55 days);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit );
        console.log("loss: ", loss );
        console.log("strategy.balanceAsset()", strategy.balanceAsset());
        console.log("strategy.balanceLST()", strategy.balanceLST());
        skip(10 days);

        skip(100 days);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit );
        console.log("loss: ", loss );
        console.log("strategy.balanceAsset()", strategy.balanceAsset());
        console.log("strategy.balanceLST()", strategy.balanceLST());

        skip(100 days);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit );
        console.log("loss: ", loss );

        skip(100 days);
        // Report profit / loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("profit: ", profit );
        console.log("loss: ", loss );

        skip(strategy.profitMaxUnlockTime());

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        console.log("redeem strategy.totalAssets() after redeem: ", strategy.totalAssets() );
        console.log("assetBalance: ", asset.balanceOf(address(strategy)) );
        console.log("assetBalance: ", strategy.balanceAsset() );
        console.log("strategy.balanceLST()", strategy.balanceLST());
        console.log("asset.balanceOf(user): ", asset.balanceOf(user) );
    }
}
