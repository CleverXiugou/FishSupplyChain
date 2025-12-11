// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // 引入 ERC20

// 🪙 1. 定义鱼币合约
contract FishToken is ERC20, Ownable {
    // 汇率：1 ETH = 10 鱼币
    uint256 public constant RATE = 10; 

    constructor() ERC20("FishCoin", "FISH") Ownable(msg.sender) {}

    // 🏦 铸币功能：用 ETH 买币
    function buyTokens() public payable {
        require(msg.value > 0, "Send ETH to buy tokens");
        // 计算兑换数量 (1 ETH = 10^18 wei, 1 Token = 10^18 units)
        // 如果发来 1 ETH，得到 10 Token
        uint256 amountToMint = msg.value * RATE;
        _mint(msg.sender, amountToMint);
    }

    // 提现合约里的 ETH (管理员功能)
    function withdrawETH() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}

contract FishSupplyChain is ERC721, ERC721Enumerable, ERC721URIStorage, ReentrancyGuard, Ownable {
    uint256 private _nextTokenId;
    
    // 🔗 引用鱼币合约地址
    FishToken public token;

    enum State { Active, Listed, Sold, Completed, Rejected }

    struct TraceData {
        uint256 timestamp;
        string location;
        int256 temperature;
    }

    struct Fish {
        string species;
        string location;
        int256 temperature;
        uint256 weight;
        uint catchTime;
        string evidenceHash;
        uint256 price;      // 价格单位现在是：鱼币 (FISH)
        State state;
        address seller;
        address fisherman;
        TraceData[] history;
        int256 maxTemp;
        bool isSpoiled;
    }

    mapping(uint256 => Fish) public fishDetails;
    // 💰 这里记录的是鱼币余额，不是 ETH
    mapping(address => uint256) public pendingWithdrawals;

    event FishCaught(uint256 indexed tokenId, address indexed fisherman, string species, int256 maxTemp);
    event FishListed(uint256 indexed tokenId, uint256 price, address seller);
    event FishSold(uint256 indexed tokenId, address buyer, uint256 price);
    event FishConfirmed(uint256 indexed tokenId, address buyer, address seller);
    event FishRejected(uint256 indexed tokenId, address buyer, address seller);
    event FundsWithdrawn(address indexed user, uint256 amount);
    event LogisticsUpdated(uint256 indexed tokenId, string location, int256 temperature, bool isSpoiled);

    // 构造函数：自动部署一个新的鱼币合约
    constructor() ERC721("Premium SeaFood", "FISH") Ownable(msg.sender) {
        token = new FishToken();
    }

    // --- 1. 捕捞 ---
    function catchFish(
        string memory _tokenURI, 
        string memory _species,
        string memory _location,
        int256 _temperature,
        uint256 _weight,
        string memory _evidenceHash,
        int256 _maxTemp
    ) public returns (uint256) {
        uint256 tokenId = generateUniqueId();
        _mint(msg.sender, tokenId);
        _setTokenURI(tokenId, _tokenURI);

        Fish storage newFish = fishDetails[tokenId];
        newFish.species = _species;
        newFish.location = _location;
        newFish.temperature = _temperature;
        newFish.weight = _weight;
        newFish.catchTime = block.timestamp;
        newFish.evidenceHash = _evidenceHash;
        newFish.price = 0;
        newFish.state = State.Active;
        newFish.seller = address(0);
        newFish.fisherman = msg.sender;
        newFish.maxTemp = _maxTemp;
        
        if (_temperature > _maxTemp) {
            newFish.isSpoiled = true;
        }

        newFish.history.push(TraceData({
            timestamp: block.timestamp,
            location: _location,
            temperature: _temperature
        }));

        emit FishCaught(tokenId, msg.sender, _species, _maxTemp);
        return tokenId;
    }

    // --- 2. 上架 (使用鱼币支付押金) ---
    // 注意：不再是 payable，而是通过 ERC20 transferFrom 扣款
    function listFish(uint256 tokenId, uint256 price) public nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(price > 0, "Price > 0");
        require(fishDetails[tokenId].state == State.Active, "Not active");
        require(!fishDetails[tokenId].isSpoiled, "Spoiled fish");

        // 💸 扣除卖家押金 (需要用户先 Approve)
        bool success = token.transferFrom(msg.sender, address(this), price);
        require(success, "Deposit failed: Allowance not enough?");

        fishDetails[tokenId].price = price;
        fishDetails[tokenId].state = State.Listed;
        fishDetails[tokenId].seller = msg.sender;

        emit FishListed(tokenId, price, msg.sender);
    }

    // --- 3. 购买 (使用鱼币支付双倍) ---
    function buyFish(uint256 tokenId) public nonReentrant {
        Fish storage fish = fishDetails[tokenId];
        require(fish.state == State.Listed, "Not listed");
        require(msg.sender != fish.seller, "Seller cannot buy");
        
        uint256 amountToPay = 2 * fish.price;

        // 💸 扣除买家双倍资金 (需要用户先 Approve)
        bool success = token.transferFrom(msg.sender, address(this), amountToPay);
        require(success, "Payment failed: Allowance not enough?");

        fish.state = State.Sold;
        _transfer(fish.seller, msg.sender, tokenId);

        emit FishSold(tokenId, msg.sender, fish.price);
    }

    // --- 4. 确认收货 (记账鱼币) ---
    function confirmReceipt(uint256 tokenId) public nonReentrant {
        Fish storage fish = fishDetails[tokenId];
        require(fish.state == State.Sold, "Not sold");
        require(ownerOf(tokenId) == msg.sender, "Only buyer");

        fish.state = State.Completed;

        uint256 price = fish.price;
        address seller = fish.seller;
        address buyer = msg.sender;

        pendingWithdrawals[seller] += 2 * price;
        pendingWithdrawals[buyer] += price;

        emit FishConfirmed(tokenId, buyer, seller);
    }

    // --- 5. 拒收 (鱼币赔付) ---
    function rejectShipment(uint256 tokenId) public nonReentrant {
        Fish storage fish = fishDetails[tokenId];
        require(fish.state == State.Sold, "Not sold");
        require(ownerOf(tokenId) == msg.sender, "Only buyer");

        fish.state = State.Rejected;

        uint256 price = fish.price;
        address buyer = msg.sender;

        // 3份鱼币全给买家
        pendingWithdrawals[buyer] += 3 * price;

        emit FishRejected(tokenId, buyer, fish.seller);
    }

    // --- 6. 提款 (提取鱼币) ---
    function withdrawPayments() public nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds");
        
        pendingWithdrawals[msg.sender] = 0;
        
        // 💸 发送 ERC20 代币
        bool success = token.transfer(msg.sender, amount);
        require(success, "Token transfer failed");
        
        emit FundsWithdrawn(msg.sender, amount);
    }

    // --- 物流与查询 (保持不变) ---
    function updateLogistics(uint256 tokenId, string memory _location, int256 _temperature) public {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        Fish storage fish = fishDetails[tokenId];
        fish.location = _location;
        fish.temperature = _temperature;
        if (_temperature > fish.maxTemp) fish.isSpoiled = true;
        fish.history.push(TraceData({timestamp: block.timestamp, location: _location, temperature: _temperature}));
        emit LogisticsUpdated(tokenId, _location, _temperature, fish.isSpoiled);
    }

    // ... (以下辅助视图函数保持不变) ...
    function getFishStatusAtTime(uint256 tokenId, uint256 queryTimestamp) public view returns (string memory, int256, uint256, bool) {
        if (fishDetails[tokenId].catchTime == 0) return ("", 0, 0, false);
        TraceData[] memory history = fishDetails[tokenId].history;
        for (int i = int(history.length) - 1; i >= 0; i--) {
            TraceData memory record = history[uint(i)];
            if (record.timestamp <= queryTimestamp) {
                return (record.location, record.temperature, record.timestamp, true);
            }
        }
        return ("", 0, 0, false);
    }
    function getFishHistory(uint256 tokenId) public view returns (TraceData[] memory) { return fishDetails[tokenId].history; }
    function getAllFishForSale() public view returns (uint256[] memory, Fish[] memory) {
        uint256 total = totalSupply();
        uint256 listedCount = 0;
        for (uint256 i = 0; i < total; i++) { if (fishDetails[tokenByIndex(i)].state == State.Listed) listedCount++; }
        uint256[] memory ids = new uint256[](listedCount);
        Fish[] memory fishes = new Fish[](listedCount);
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < total; i++) {
            uint256 tokenId = tokenByIndex(i);
            if (fishDetails[tokenId].state == State.Listed) { ids[currentIndex] = tokenId; fishes[currentIndex] = fishDetails[tokenId]; currentIndex++; }
        }
        return (ids, fishes);
    }
    function generateUniqueId() private view returns (uint256) {
        uint256 randomHash = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
        return 1000000000000000 + (randomHash % 9000000000000000);
    }
    function getFishByOwner(address _owner) public view returns (uint256[] memory, Fish[] memory) {
        uint256 balance = balanceOf(_owner);
        uint256[] memory ids = new uint256[](balance);
        Fish[] memory fishes = new Fish[](balance);
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = tokenOfOwnerByIndex(_owner, i);
            ids[i] = tokenId;
            fishes[i] = fishDetails[tokenId];
        }
        return (ids, fishes);
    }
    // Overrides
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) { return super._update(to, tokenId, auth); }
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) { super._increaseBalance(account, value); }
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) { return super.tokenURI(tokenId); }
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, ERC721URIStorage) returns (bool) { return super.supportsInterface(interfaceId); }
}