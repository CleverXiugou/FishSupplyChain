# 🐟 基于区块链的鱼类溯源与担保交易系统
这是一个基于以太坊（Solidity）和 Foundry 框架开发的去中心化应用（DApp）。该项目实现了鱼类从捕捞到销售的全流程溯源，并引入了双向押金担保交易和冷链温控机制，确保交易安全与食品安全。

## ✨ 核心功能
🎣 捕捞上链：记录鱼类品种、重量、捕捞时间、初始温度及位置。

🌡️ 冷链追踪：支持物流过程中更新位置与温度，若超过安全阈值自动标记变质。

💰 担保交易：买卖双方需支付押金（卖家 1x，买家 2x），确认收货后资金解冻。

❌ 拒收赔付：若买家拒绝收货，卖家的押金将赔付给买家。

🔍 全程溯源：支持查看所有权变更历史及冷链温控轨迹快照。

## 🛠️ 快速开始 (Quick Start)
请按照以下步骤在本地运行此项目。

### 1. 安装 Foundry 开发框架
本项目使用 Foundry 进行智能合约的开发与测试。

MacOS / Linux: 打开终端执行以下命令：

```curl -L https://foundry.paradigm.xyz | bash```

安装脚本运行完成后，执行以下命令使配置生效：

```foundryup```

Windows: 建议安装 WSL (Windows Subsystem for Linux) 后，在 WSL 环境中执行上述命令。

### 2. 下载代码与编译
克隆项目到本地并安装依赖：

### 克隆仓库 (请替换为您的实际仓库地址)
```git clone <仓库地址>```

### 进入目录
```cd fish-supply-chain```

### 安装依赖 (OpenZeppelin 等)
```forge install```

### 编译合约
```forge build```

### 3. 启动本地测试链 (Anvil)
打开一个新的终端窗口（终端 A），启动 Foundry 自带的本地节点：

```anvil```

注意：请保持此窗口一直运行。你会看到一系列生成的私钥 (Private Keys) 和地址，稍后会用到。

### 4. 部署智能合约
回到原来的终端窗口（终端 B），执行部署脚本：

```forge script script/DeployFish.s.sol:DeployFish --rpc-url http://127.0.0.1:8545 --broadcast```

部署成功后，终端会输出类似以下信息，请找到 Contract Address：

Contract Address: 0x5FbDB2315678afecb367f032d93F642f64180aa3

### 5. 配置前端
使用代码编辑器（如 VS Code）打开 index.html 文件。

找到第 160 行左右的 CONTRACT_ADDRESS 常量。

将其替换为您刚刚部署得到的合约地址：

// ⚠️ 修改此处为您的新合约地址
const CONTRACT_ADDRESS = "0x5FbDB2315678afecb367f032d93F642f64180aa3";

保存文件。

### 6. 启动前端页面

在项目根目录下（终端 B），启动一个简单的本地服务器：

### 如果安装了 Python 3
```python3 -m http.server 8000```

或者如果您使用 VS Code，可以直接右键 index.html 选择 "Open with Live Server"。

### 7. 浏览器交互与 MetaMask 配置

在浏览器访问：http://localhost:8000

### 配置 MetaMask 连接本地链：

网络名称: Anvil Localhost

RPC URL: http://127.0.0.1:8545

链 ID: 31337

货币符号: ETH

### 导入测试账户：

复制 终端 A (Anvil) 中列出的任意一个 Private Key。

在 MetaMask 中选择“导入账户”，粘贴私钥。

点击网页上的 "🦊 连接钱包" 即可开始使用！

### 🧪 运行测试
本项目包含完整的自动化测试脚本。在终端执行以下命令即可运行测试：

```forge test```

### 查看详细的测试覆盖率和日志：

```forge test -vv```
