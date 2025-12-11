// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FishSupplyChain is ERC721, ERC721Enumerable, ERC721URIStorage, ReentrancyGuard, Ownable {
    uint256 private _nextTokenId;

    enum State { Active, Listed, Sold, Completed }

    struct TraceData {
        uint256 timestamp;   // 记录时间
        string location;     // 当前位置
        int256 temperature;  // 当前温度
    }

    struct Fish {
        string species;
        string location;     
        int256 temperature;  
        uint256 weight;
        uint catchTime;
        string evidenceHash;
        uint256 price;
        State state;
        address seller;
        address fisherman;
        TraceData[] history;
    }

    mapping(uint256 => Fish) public fishDetails;
    mapping(address => uint256) public pendingWithdrawals;

    event FishCaught(uint256 indexed tokenId, address indexed fisherman, string species);
    event FishListed(uint256 indexed tokenId, uint256 price, address seller);
    event FishSold(uint256 indexed tokenId, address buyer, uint256 price);
    event FishConfirmed(uint256 indexed tokenId, address buyer, address seller);
    event FundsWithdrawn(address indexed user, uint256 amount);
    event LogisticsUpdated(uint256 indexed tokenId, string location, int256 temperature);

    constructor() ERC721("Premium SeaFood", "FISH") Ownable(msg.sender) {}

    // --- 1. 捕捞 ---
    function catchFish(
        string memory _tokenURI, 
        string memory _species,
        string memory _location,
        int256 _temperature,
        uint256 _weight,
        string memory _evidenceHash
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

        // 记录初始点
        newFish.history.push(TraceData({
            timestamp: block.timestamp,
            location: _location,
            temperature: _temperature
        }));

        emit FishCaught(tokenId, msg.sender, _species);
        return tokenId;
    }

    // --- 2. 更新物流 ---
    function updateLogistics(uint256 tokenId, string memory _location, int256 _temperature) public {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        
        Fish storage fish = fishDetails[tokenId];
        fish.location = _location;
        fish.temperature = _temperature;

        fish.history.push(TraceData({
            timestamp: block.timestamp,
            location: _location,
            temperature: _temperature
        }));

        emit LogisticsUpdated(tokenId, _location, _temperature);
    }

    // --- 3. 根据时间戳查询状态 ---
    // 返回指定时间点鱼的位置和温度
    function getFishStatusAtTime(uint256 tokenId, uint256 queryTimestamp) public view returns (string memory location, int256 temperature, uint256 recordedTime, bool found) {
        require(ownerOf(tokenId) != address(0), "Fish does not exist");
        
        TraceData[] memory history = fishDetails[tokenId].history;
        
        // 倒序遍历，找到第一个早于或等于 queryTimestamp 的记录
        for (int i = int(history.length) - 1; i >= 0; i--) {
            TraceData memory record = history[uint(i)];
            if (record.timestamp <= queryTimestamp) {
                return (record.location, record.temperature, record.timestamp, true);
            }
        }
        
        // 如果查询时间早于捕捞时间，返回空
        return ("", 0, 0, false);
    }

    // --- 4. 获取完整历史 ---
    function getFishHistory(uint256 tokenId) public view returns (TraceData[] memory) {
        return fishDetails[tokenId].history;
    }

    // --- 上架功能  ---
    function listFish(uint256 tokenId, uint256 price) public payable nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        require(price > 0, "Price > 0");
        require(fishDetails[tokenId].state == State.Active, "Not active");
        require(msg.value == price, "Deposit required");

        fishDetails[tokenId].price = price;
        fishDetails[tokenId].state = State.Listed;
        fishDetails[tokenId].seller = msg.sender;

        emit FishListed(tokenId, price, msg.sender);
    }

    function buyFish(uint256 tokenId) public payable nonReentrant {
        Fish storage fish = fishDetails[tokenId];
        require(fish.state == State.Listed, "Not listed");
        require(msg.sender != fish.seller, "Seller cannot buy");
        require(msg.value == 2 * fish.price, "2x Price required");

        fish.state = State.Sold;
        _transfer(fish.seller, msg.sender, tokenId);

        emit FishSold(tokenId, msg.sender, fish.price);
    }

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

    function withdrawPayments() public nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds");
        pendingWithdrawals[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        emit FundsWithdrawn(msg.sender, amount);
    }

    // --- 辅助功能 ---
    function getAllFishForSale() public view returns (uint256[] memory, Fish[] memory) {
        uint256 total = totalSupply();
        uint256 listedCount = 0;
        for (uint256 i = 0; i < total; i++) {
            if (fishDetails[tokenByIndex(i)].state == State.Listed) listedCount++;
        }

        uint256[] memory ids = new uint256[](listedCount);
        Fish[] memory fishes = new Fish[](listedCount);
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < total; i++) {
            uint256 tokenId = tokenByIndex(i);
            if (fishDetails[tokenId].state == State.Listed) {
                ids[currentIndex] = tokenId;
                fishes[currentIndex] = fishDetails[tokenId];
                currentIndex++;
            }
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
    function _update(address to, uint256 tokenId, address auth) internal override(ERC721, ERC721Enumerable) returns (address) {
        return super._update(to, tokenId, auth);
    }
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}