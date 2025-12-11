// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FishSupplyChain.sol";

contract FishTest is Test {
    FishSupplyChain public fishContract;
    address public fisherman = address(1);
    address public buyer = address(2);

    function setUp() public {
        fishContract = new FishSupplyChain();
        vm.deal(fisherman, 100 ether);
        vm.deal(buyer, 100 ether);
    }

    function test_FullFlow_WithWithdraw() public {
        // 1. 捕鱼
        vm.startPrank(fisherman);
        uint256 tokenId = fishContract.catchFish("uri", "Tuna", "Ocean", -5, 5000, "hash");

        // 2. 上架 (付押金 1 ETH)
        fishContract.listFish{value: 1 ether}(tokenId, 1 ether);
        vm.stopPrank();

        // 3. 购买 (付 2 ETH)
        vm.startPrank(buyer);
        fishContract.buyFish{value: 2 ether}(tokenId);

        // 4. 确认收货 (资金解冻到合约账本)
        // 记录确认前的钱包余额
        uint256 buyerWalletBefore = buyer.balance;

        fishContract.confirmReceipt(tokenId);

        // 此时，买家的钱包余额应该没有变化（钱还在合约里）
        assertEq(buyer.balance, buyerWalletBefore);

        // 检查合约里的待提现余额 (买家应退回 1 ETH 押金)
        uint256 pending = fishContract.pendingWithdrawals(buyer);
        assertEq(pending, 1 ether);

        // 5. 提现
        fishContract.withdrawPayments();

        // 此时，买家钱包余额应该增加了 1 ETH
        assertEq(buyer.balance, buyerWalletBefore + 1 ether);

        vm.stopPrank();
    }
}
