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

    enum State {
        Active,
        Listed,
        Sold,
        Completed,
        Rejected
    }

    struct TraceData {
        // 更新时间戳
        uint256 timestamp;
        // 当前鱼的位置
        string location;
        // 当前鱼的温度
        int256 temperature;
    }

    struct Fish {
        // 鱼的种类
        string species;
        // 捕鱼的位置
        string location;
        // 捕捞时的温度
        int256 temperature;
        // 鱼的重量
        uint256 weight;
        // 捕捞时间
        uint256 catchTime;
        // 鱼的证据哈希
        string evidenceHash;
        // 鱼的价格
        uint256 price;
        // 当前鱼的状态，State在上面已经被定义为5中状态
        State state;
        // 卖家
        address seller;
        // 渔民
        address fisherman;
        // 鱼的全状态模式
        TraceData[] history;
    }
    // 鱼的TokenId => 一条鱼
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
    // _tokenURI是用来链接鱼的其他信息的，存储在其他链上，当前项目没有使用到
    // _evidenceHash可理解为指纹，根据不同场景可以被认为捕鱼许可证，检疫证明等，当前项目暂未使用
    function catchFish(
        string memory _tokenURI,
        string memory _species,
        string memory _location,
        int256 _temperature,
        uint256 _weight,
        string memory _evidenceHash
    ) public returns (uint256) {
        // 生成一个独一无二的16位数字tokenId
        uint256 tokenId = generateUniqueId();
        // ERC721标准库提供的内部函数，铸币操作，tokenId为xxx的鱼属于msg.sender这个渔民了
        _mint(msg.sender, tokenId);
        // 绑定说明书：tokenId的鱼具体信息去_tokenURI查看吧
        _setTokenURI(tokenId, _tokenURI);

        Fish storage newFish = fishDetails[tokenId];
        newFish.species = _species;
        newFish.location = _location;
        newFish.temperature = _temperature;
        newFish.weight = _weight;
        newFish.catchTime = block.timestamp;
        newFish.evidenceHash = _evidenceHash;
        newFish.price = 0;
        // 初始化鱼的状态为未上架，只上链了
        newFish.state = State.Active;
        // 因为还没有卖鱼，卖家地址设置为0地址
        newFish.seller = address(0);
        newFish.fisherman = msg.sender;
        // 把鱼的信息放到数组中
        newFish.history.push(TraceData({timestamp: block.timestamp, location: _location, temperature: _temperature}));

        emit FishCaught(tokenId, msg.sender, _species);
        return tokenId;
    }

    // --- 2. 更新物流状态 ---
    // 需要传入鱼的tokenId，当前位置，当前温度
    function updateLogistics(uint256 tokenId, string memory _location, int256 _temperature) public {
        // 只有鱼当前的所有者可以更新信息
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        // 把鱼之前的信息先赋值进入
        Fish storage fish = fishDetails[tokenId];
        // 更新当前位置和温度
        fish.location = _location;
        fish.temperature = _temperature;
        // 把鱼的信息放入到数组中
        fish.history.push(TraceData({timestamp: block.timestamp, location: _location, temperature: _temperature}));

        emit LogisticsUpdated(tokenId, _location, _temperature);
    }

    // --- 3. 查询特定时间状态 ---
    function getFishStatusAtTime(uint256 tokenId, uint256 queryTimestamp)
        public
        view
        returns (string memory location, int256 temperature, uint256 recordedTime, bool found)
    {
        // 这条鱼还没有被捕捞上来
        if (ownerOf(tokenId) == address(0)) return ("", 0, 0, false);

        // 获取鱼的历史数据
        TraceData[] memory history = fishDetails[tokenId].history;
        // 遍历鱼的历史数据
        for (int256 i = int256(history.length) - 1; i >= 0; i--) {
            TraceData memory record = history[uint256(i)];
            if (record.timestamp <= queryTimestamp) {
                return (record.location, record.temperature, record.timestamp, true);
            }
        }
        return ("", 0, 0, false);
    }

    // 查询鱼的全部历史数据
    function getFishHistory(uint256 tokenId) public view returns (TraceData[] memory) {
        return fishDetails[tokenId].history;
    }

    // --- 交易上架功能，支持二手转卖 ---
    function listFish(uint256 tokenId, uint256 price) public payable nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();
        // price是uint类型，所以没有负数，只需要保证上架价格不等于0就行
        if (price == 0) revert InvalidPrice();
        // 要保证鱼之前的状态是已上链或已收货
        if (fishDetails[tokenId].state != State.Active && fishDetails[tokenId].state != State.Completed) {
            revert InvalidState();
        }
        // 保证传入合约的钱（押金）等于鱼的售价
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
        // 鱼必须已经上架
        if (fish.state != State.Listed) revert InvalidState();
        // 自己不能买自己卖的鱼
        if (msg.sender == fish.seller) revert NotSeller();
        // 传入合约的钱是押金+售价
        if (msg.value != 2 * fish.price) revert IncorrectValue();

        // 更新鱼的状态为已售出
        fish.state = State.Sold;
        // 更改鱼的归属权：_transfer(from, to, tokenId)
        _transfer(fish.seller, msg.sender, tokenId);

        // 记录买家冻结资金 (双倍货款)
        frozenFunds[msg.sender] += msg.value;

        emit FishSold(tokenId, msg.sender, fish.price);
    }

    // 确认收货（鱼没有问题）
    function confirmReceipt(uint256 tokenId) public nonReentrant {
        Fish storage fish = fishDetails[tokenId];

        // 确实收货的鱼必须要为已售出状态
        if (fish.state != State.Sold) revert InvalidState();
        // 只有买家可以确认收货
        if (ownerOf(tokenId) != msg.sender) revert OnlyBuyer();

        // 更改鱼的状态为已收货
        fish.state = State.Completed;

        // 记录鱼的归属权变化
        uint256 price = fish.price;
        address seller = fish.seller;
        address buyer = msg.sender;

        // 解除冻结
        frozenFunds[seller] -= price; // 卖家押金解除
        frozenFunds[buyer] -= 2 * price; // 买家资金解除

        // 结算可提现
        pendingWithdrawals[seller] += 2 * price; // 卖家得: 货款+押金
        pendingWithdrawals[buyer] += price; // 买家得: 退回的一半押金

        emit FishConfirmed(tokenId, buyer, seller);
    }

    // 拒绝收货（鱼有问题）
    function rejectFish(uint256 tokenId) public nonReentrant {
        Fish storage fish = fishDetails[tokenId];

        // 鱼当前的状态为已出售
        if (fish.state != State.Sold) revert InvalidState();
        // 只有买家可以调用这个函数
        if (ownerOf(tokenId) != msg.sender) revert OnlyBuyer();

        // 更新鱼的状态
        fish.state = State.Rejected;

        // 记录鱼的归属权信息
        uint256 price = fish.price;
        address seller = fish.seller;
        address buyer = msg.sender;

        // 解除冻结
        frozenFunds[seller] -= price; // 卖家押金解除(但被没收)
        frozenFunds[buyer] -= 2 * price; // 买家资金解除

        // 结算可提现 (惩罚逻辑)
        // 买家获得: 自己付出的2份 + 卖家赔偿的1份 = 3份
        pendingWithdrawals[buyer] += 3 * price;

        emit FishRejected(tokenId, buyer, seller);
    }
    
    function destroyFish(uint256 tokenId) public nonReentrant {
        if (ownerOf(tokenId) != msg.sender) revert NotOwner();

        Fish storage fish = fishDetails[tokenId];
        require(fish.state == State.Active || fish.state == State.Completed, "Cannot destroy fish NFT");
        _burn(tokenId);
    }

    function withdrawPayments() public nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoFunds();

        pendingWithdrawals[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: amount}("");
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
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
