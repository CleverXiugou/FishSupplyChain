// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FishSupplyChain is ERC721, ERC721Enumerable, ERC721URIStorage, ReentrancyGuard, Ownable {
    uint256 private _nextTokenId;

    // --- Custom Errors ---
    error NotOwner();
    error NotSeller();
    error OnlyBuyer();
    error InvalidState();
    error InvalidPrice();
    error IncorrectValue();
    error NoFunds();
    error FishDoesNotExist();

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
        uint256 price;
        State state;
        address seller;
        address fisherman;
        TraceData[] history;
    }

    mapping(uint256 => Fish) public fishDetails;
    
    // 1. 可提现余额 (已结算/已解冻)
    mapping(address => uint256) public pendingWithdrawals;
    // 2. 冻结资金 (质押中/交易中) - 新增
    mapping(address => uint256) public frozenFunds;

    event FishCaught(uint256 indexed tokenId, address indexed fisherman, string species);
    event FishListed(uint256 indexed tokenId, uint256 price, address seller);
    event FishSold(uint256 indexed tokenId, address buyer, uint256 price);
    event FishConfirmed(uint256 indexed tokenId, address buyer, address seller);
    event FishRejected(uint256 indexed tokenId, address buyer, address seller); 
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
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        
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

    // --- 3. 查询特定时间状态 ---
    function getFishStatusAtTime(uint256 tokenId, uint256 queryTimestamp) public view returns (string memory location, int256 temperature, uint256 recordedTime, bool found) {
        if (ownerOf(tokenId) == address(0)) return ("", 0, 0, false);

        TraceData[] memory history = fishDetails[tokenId].history;
        for (int i = int(history.length) - 1; i >= 0; i--) {
            TraceData memory record = history[uint(i)];
            if (record.timestamp <= queryTimestamp) {
                return (record.location, record.temperature, record.timestamp, true);
            }
        }
        return ("", 0, 0, false);
    }

    function getFishHistory(uint256 tokenId) public view returns (TraceData[] memory) {
        return fishDetails[tokenId].history;
    }

    // --- 交易功能 ---
    function listFish(uint256 tokenId, uint256 price) public payable nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (price == 0) revert InvalidPrice();
        if (fishDetails[tokenId].state != State.Active) revert InvalidState();
        if (msg.value != price) revert IncorrectValue();

        fishDetails[tokenId].price = price;
        fishDetails[tokenId].state = State.Listed;
        fishDetails[tokenId].seller = msg.sender;
        
        // 记录卖家冻结资金 (押金)
        frozenFunds[msg.sender] += price;

        emit FishListed(tokenId, price, msg.sender);
    }

    function buyFish(uint256 tokenId) public payable nonReentrant {
        Fish storage fish = fishDetails[tokenId];
        
        if (fish.state != State.Listed) revert InvalidState();
        if (msg.sender == fish.seller) revert NotSeller();
        if (msg.value != 2 * fish.price) revert IncorrectValue();

        fish.state = State.Sold;
        _transfer(fish.seller, msg.sender, tokenId);

        // 记录买家冻结资金 (双倍货款)
        frozenFunds[msg.sender] += msg.value;

        emit FishSold(tokenId, msg.sender, fish.price);
    }

    function confirmReceipt(uint256 tokenId) public nonReentrant {
        Fish storage fish = fishDetails[tokenId];
        
        if (fish.state != State.Sold) revert InvalidState();
        if (ownerOf(tokenId) != msg.sender) revert OnlyBuyer();

        fish.state = State.Completed;

        uint256 price = fish.price;
        address seller = fish.seller;
        address buyer = msg.sender;

        // 解除冻结
        frozenFunds[seller] -= price;      // 卖家押金解除
        frozenFunds[buyer] -= 2 * price;   // 买家资金解除

        // 结算可提现
        pendingWithdrawals[seller] += 2 * price; // 卖家得: 货款+押金
        pendingWithdrawals[buyer] += price;      // 买家得: 退回的一半押金

        emit FishConfirmed(tokenId, buyer, seller);
    }

    // --- 拒绝收货 ---
    function rejectFish(uint256 tokenId) public nonReentrant {
        Fish storage fish = fishDetails[tokenId];
        
        if (fish.state != State.Sold) revert InvalidState();
        if (ownerOf(tokenId) != msg.sender) revert OnlyBuyer();

        fish.state = State.Rejected;
        
        uint256 price = fish.price;
        address seller = fish.seller;
        address buyer = msg.sender;
        
        // 解除冻结
        frozenFunds[seller] -= price;      // 卖家押金解除(但被没收)
        frozenFunds[buyer] -= 2 * price;   // 买家资金解除

        // 结算可提现 (惩罚逻辑)
        // 买家获得: 自己付出的2份 + 卖家赔偿的1份 = 3份
        pendingWithdrawals[buyer] += 3 * price;

        emit FishRejected(tokenId, buyer, seller);
    }

    function withdrawPayments() public nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoFunds();

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