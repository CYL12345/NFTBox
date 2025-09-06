// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract NFTPoolManager is IERC721Receiver, ReentrancyGuard, Ownable{
    struct Item{
        address token;
        uint256 id;
    }

    mapping(uint8 => Item[]) public pools;//物品稀有度映射
    mapping(bytes32 => uint256) private _indexOf; //NFT在池中的索引 key=哈希值（NFT合约+tokenId+稀有度），value=在数组中的索引（+1避免0值歧义）
    mapping(address => bool) public authorizedCaller; // 授权调用者映射

    // 事件：NFT存入成功
    event Deposited(address indexed from, address indexed token, uint256 indexed tokenId, uint8 rarity);
    // 事件：NFT提取成功
    event ItemClaimed(address indexed to, address indexed token, uint256 indexed tokenId, uint8 rarity);
    // 事件：NFT紧急提取成功
    event Withdrawn(address indexed to, address indexed token, uint256 indexed tokenId);
    // 事件：授权调用者设置成功
    event CallerSet(address indexed caller, bool allowed);

    error NoCaller();
    error InvaildData();
    error ErrorPool();

    modifier OnlyCaller() {
        if(owner() == msg.sender || authorizedCaller[msg.sender]){
            revert NoCaller();
        }
        _;
    }

    constructor() Ownable(msg.sender){}

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4){
        //校验数据合法
        if(data.length ==32 || data.length ==1){
            revert InvaildData();
        }
        uint8 rarity;
        if(data.length ==1){
            rarity = uint8(data[0]);
        }
        if(data.length ==32){
            rarity = abi.decode(data,(uint8));
        }

        //NFT存入稀有度池
        Item memory item = Item({
            token:msg.sender,
            id:tokenId
        });
        pools[rarity].push(item);

        //记录池中索引 索引为数组长度即1-based
        bytes32 key = _itemKey(msg.sender,tokenId,rarity);
        _indexOf[key] = pools[rarity].length;

        emit Deposited(from,msg.sender,tokenId,rarity);
        // 返回ERC721Receiver，证明合约已正确处理NFT接收
        return this.onERC721Received.selector;
    }

    //授权管理
    function setAuthorizedCaller(address caller,bool allowed) external onlyOwner{
        authorizedCaller[caller] = allowed;
        emit CallerSet(caller, allowed);
    }


    //随机提取NFT给抽奖者
    function popItem(
        uint8 rarity,
        uint256 randomness,
        address to
    )external nonReentrant OnlyCaller returns(address token,uint256 tokenId){
        Item[] storage arr = pools[rarity];
        if(arr.length == 0){
            revert ErrorPool();
        }
        uint256 len = arr.length;
        uint256 idx = randomness % len;
        Item memory chosen = arr[idx];

        //Swap-and-pop
        uint256 lastIdx = len-1;
        if(idx != lastIdx){
            Item memory lastItem = arr[lastIdx];
            arr[idx] = lastItem;
            bytes32 lastKey = _itemKey(lastItem.token,lastItem.id,rarity);
            _indexOf[lastKey] = idx + 1;
        }
        //删除最后的元素
        arr.pop();

        //删除选中的NFT的索引映射
        bytes32 chosenKey = _itemKey(chosen.token,chosen.id,rarity);
        delete _indexOf[chosenKey];

        //选中的NFT转给接受者
        IERC721(chosen.token).safeTransferFrom(address(this),to,chosen.id);
        emit ItemClaimed(to, chosen.token, chosen.id, rarity);
        return (chosen.token,chosen.id);
    }

    //-----辅助函数-----
    function poolLength(uint8 rarity) external view returns(uint256){
        return pools[rarity].length;
    }

    function itemAt(uint8 rarity,uint256 index) external view returns(address token,uint256 id){
        Item storage item = pools[rarity][index];
        return (item.token,item.id);
    }

    function isInpool(address token,uint256 tokenId,uint8 rarity) external view returns(bool){
        bytes32 key = _itemKey(token,tokenId,rarity);
        return _indexOf[key]!=0;
    }

    // --------------------
    // 紧急操作/管理员提取：用于用户找回NFT或管理员移除异常存入的NFT
    // --------------------
    /**
     * @dev 管理员提取指定NFT（仅合约所有者可调用）
     * 功能：若NFT在池中，先从池中移除，再将NFT转账给接收者
     * @param token NFT合约地址
     * @param tokenId NFT的tokenId
     * @param rarity 稀有度等级
     * @param to NFT接收者地址
     */
    function adminWithdrawToken(address token, uint256 tokenId, uint8 rarity, address to) external onlyOwner nonReentrant {
        // 计算NFT的索引映射key
        bytes32 key = _itemKey(token, tokenId, rarity);
        uint256 idx1 = _indexOf[key];

        // 若NFT在池中，先通过swap-and-pop移除
        if (idx1 != 0) {
            // 转换为0-based索引
            uint256 idx = idx1 - 1;
            Item[] storage arr = pools[rarity];
            uint256 lastIdx = arr.length - 1;

            // 交换选中NFT与最后一个NFT
            if (idx != lastIdx) {
                Item memory lastItem = arr[lastIdx];
                arr[idx] = lastItem;
                // 更新交换后NFT的索引映射
                bytes32 lastKey = _itemKey(lastItem.token, lastItem.id, rarity);
                _indexOf[lastKey] = idx + 1;
            }
            // 删除最后一个元素
            arr.pop();
            // 删除原NFT的索引映射
            delete _indexOf[key];
        }

        // 将NFT转账给接收者（确保合约持有该NFT）
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
        // 触发紧急提取事件
        emit Withdrawn(to, token, tokenId);
    }

    // --------------------
    // 内部辅助函数
    // --------------------
    /**
     * @dev 生成NFT的唯一索引key（哈希值）
     * @param token NFT合约地址
     * @param tokenId NFT的tokenId
     * @param rarity 稀有度等级
     * @return 哈希后的key
     */
    function _itemKey(address token, uint256 tokenId, uint8 rarity) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(token, tokenId, rarity));
    }

    // --------------------
    // 紧急救援：提取误转入合约的NFT（未指定稀有度的情况）
    // --------------------
    /**
     * @dev 管理员救援误转入的NFT（仅合约所有者可调用）
     * 功能：用于提取未通过onERC721Received存入、直接转入的NFT
     * @param token NFT合约地址
     * @param tokenId NFT的tokenId
     * @param to 接收者地址
     */
    function rescueERC721(address token, uint256 tokenId, address to) external onlyOwner {
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
    }
}