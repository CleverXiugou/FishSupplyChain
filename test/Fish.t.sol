// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 引入 Foundry 的标准测试库和主合约代码
import "forge-std/Test.sol";
import "../src/FishSupplyChain.sol";

contract FishTest is Test {
    // 创建合约实例
    FishSupplyChain public fishContract;

    // 创建两个角色，充当渔夫和买家
    address public fisherman = address(1);
    address public buyer = address(2);

    // 初始化
    function setUp() public {
        // 部署一个全新的合约实例
        fishContract = new FishSupplyChain();
        // 给两个角色发钱：vm.deal()
        vm.deal(fisherman, 100 ether);
        vm.deal(buyer, 100 ether);
    }

    function test_FullFlow_WithWithdraw() public {
        // 1. 捕鱼，以下所有操作都伪装成fisherman发起的，startPrank和stopPrank配对
        vm.startPrank(fisherman);
        // 捕鱼测试，传入的参数是主合约catchFish需要的参数
        uint256 tokenId = fishContract.catchFish("uri", "Tuna", "Ocean", -5, 5000, "hash");

        // 2. 上架 (付押金 1 ETH)，中括号内为上架附带的押金，小括号为listFish需要的参数
        fishContract.listFish{value: 1 ether}(tokenId, 1 ether);
        // 结束fisherman的伪装
        vm.stopPrank();

        // 3. 购买 (付 2 ETH)，切换成买家角色
        vm.startPrank(buyer);
        // 函数附带两倍售价：押金+售价
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
