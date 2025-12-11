# 🐟 Fish Supply Chain DApp (基于区块链的鱼类溯源与交易系统)
这是一个基于以太坊的去中心化应用 (DApp)，旨在解决海鲜供应链中的信任与溯源问题。项目利用智能合约实现了从捕捞到餐桌的全流程数据记录，并引入了双向押金机制 (Dual Deposit) 这里的担保交易逻辑，确保买卖双方诚实履约。

## ✨ 主要功能 (Key Features)
### 1. 🔗 全流程溯源 (Traceability)
* 捕捞上链：渔民记录鱼的品种、重量、初始位置、温度和捕捞时间，生成唯一的 NFT。

* 冷链追踪：物流过程中可随时更新位置和温度数据。

* 时空快照：支持查询特定时间点的冷链状态（位置/温度），防止数据造假。

### 2. 🛡️ 担保交易机制 (Escrow & Deposit)
为了防止欺诈，系统采用了类似博弈论的押金机制：

* 卖家上架：需支付 1x 价格 作为押金（冻结在合约中）。

* 买家购买：需支付 2x 价格（1份货款 + 1份押金，共冻结在合约中）。

* 正常收货：

卖家获得：2x 资金（退回押金 + 收到货款）。

买家获得：1x 资金（退回押金）。

* 拒绝收货 (惩罚机制)：

若买家拒收（如货物变质），合约触发惩罚。

买家获得：3x 资金（全额退款 + 没收卖家的押金作为赔偿）。

### 3. 💰 资金管理系统
冻结资金 (Frozen Funds)：实时显示用户当前锁定在未完成订单中的押金和货款。

可提现余额 (Pending Withdrawals)：交易结算（完成或拒收）后，资金自动解冻至此，用户可一键提现至钱包。

### 4. 🖥️ 前端交互
可视化时间轴：清晰展示捕捞、上架、购买、成交/拒收的全过程。

市场筛选：支持按私有、在售、待收货等状态筛选 NFT。

## 🛠️ 技术栈 (Tech Stack)
* 智能合约: Solidity (ERC721 标准)

* 开发框架: Foundry (Forge, Anvil, Cast)

* 前端: HTML5, CSS3 (原生), Ethers.js v6

* 网络: 本地测试网 (Anvil) 或以太坊测试网 (Sepolia/Goerli)

## 🚀 快速开始 (Quick Start)
按照以下步骤在本地运行项目：

### 1. 环境准备
确保你已经安装了以下工具：

1. Git

2. Foundry (包含 forge, anvil)

3. MetaMask 浏览器插件

### 2. 克隆仓库

```git clone https://github.com/CleverXiugou/FishSupplyChain.git```

```cd FishSupplyChain```

### 3. 启动本地区块链节点

打开一个新的终端窗口，启动 Anvil：

```anvil```

注意：Anvil 启动后会提供一组测试私钥和地址，请将其中一个私钥导入 MetaMask 用于测试。

### 4. 部署智能合约

在项目根目录下（保持 Anvil 运行），执行部署脚本：

```forge script script/DeployFish.s.sol --broadcast --rpc-url http://127.0.0.1:8545```

### 5. 连接前端

复制合约地址：部署成功后，终端会显示 Contract Address: 0x...。

修改前端配置：打开 index.html，找到以下代码行并替换为你的新地址：

const CONTRACT_ADDRESS = "你的合约地址粘贴在这里";

运行前端： 你可以直接双击打开 index.html，或者使用 VS Code 的 "Live Server" 插件（推荐）。 或者使用 Python 快速启动服务：

```python3 -m http.server 8000```

访问 http://localhost:8000。

