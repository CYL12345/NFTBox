// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
contract LootBoxVRF is VRFConsumerBaseV2Plus{
    IVRFCoordinatorV2Plus COORDINATOR;
    // VRF配置
    address private vrfCoordinator = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B; //合约地址
    bytes32 private keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae; //对应VRF配置的gaslane (费用配置)
    uint256 private subId;  //订阅号
    uint32 public  callbackGasLimit = 200000;//回调时候的最大gas费用
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;

    //盲盒&池子
    struct Class{
        //使用 swap-and-pop保证O(1)取出一个未发放的奖品
        uint256[] items;  //items[k] = 奖品Id
        mapping(uint256 => uint256) idex;//奖品id => 在items的索引
        uint256 remaining; //剩余数量（==items.length）
    }
    Class[] public classes;//[SSR,SR,R,N]
    uint32 public totalRemaining;//所有剩余之和

    //====== 用户请求状态 ======
    enum Status {None,Requested,Fulfilled}
    struct Ask{
        Status status;
        address buyer;
        uint256 randomness;//VRF回调写入
    }

    mapping(uint256 => Ask) public asks;//requestId => Ask

    event BoxPurchased(address indexed buyer,uint256 indexed requestId);
    event BoxOpened(address indexed buyer,uint8 rarity,uint256 itemId);
    event RandomsRequest(uint256 requestId,address indexed user);

    error Insufficientvalue();
    error BadStats();
    constructor(
        uint256 _subscriptionId
    ) VRFConsumerBaseV2Plus(vrfCoordinator){
        COORDINATOR = IVRFCoordinatorV2Plus(vrfCoordinator);
        subId = _subscriptionId;
    }

    function requestRandomWords() public returns(uint256){
        VRFV2PlusClient.RandomWordsRequest memory randomWordRequest = VRFV2PlusClient.RandomWordsRequest({
            keyHash:keyHash,
            subId:subId,
            requestConfirmations:requestConfirmations,
            callbackGasLimit:callbackGasLimit,
            numWords:numWords,
            extraArgs:""
        });
        uint256 requestId = COORDINATOR.requestRandomWords(randomWordRequest);
        emit RandomsRequest(requestId,msg.sender);
        return requestId;
    }

    //用户购买盲盒 -> 立刻申请VRF 随机数
    function buyBox() external payable returns(uint256 requestId){
        /** 
         *      if(msg.value < price){
                    revert Insufficientvalue();
                }
        */
       requestId = requestRandomWords();
       asks[requestId] = Ask({
            status:Status.Requested,
            buyer:msg.sender,
            randomness: 0            
       });
        emit BoxPurchased(msg.sender,requestId);
    }

    //VRF回调
    function fulfillRandomWords(uint256 requestId,uint256[] calldata randomWords)internal override{
        Ask storage a = asks[requestId];
        if(a.status != Status.Requested){
            revert BadStats();
        }
        //修改随机数
        a.randomness = randomWords[0];
        uint256 r = randomWords[0] % totalRemaining;
        uint8 pickedClass;
        uint256 acc = 0;
        for(uint8 i=0;i<classes.length;i++){
            acc += classes[i].remaining;
            if( r<acc ){
                pickedClass = i;
                break;
            }
        }
        //在稀有度池里抽具体奖品（swap and pop)
        Class storage C = classes[pickedClass];
        uint256 r2 = uint256(keccak256(abi.encode(r,"item"))) % C.remaining;
        uint256 itemId = C.items[r2];

        //swap and pop
        uint256 lastIdx = C.remaining - 1;
        if(r2 != lastIdx){
            uint256 lastItem = C.items[lastIdx];
            C.items[r2] = lastItem;
            C.idex[lastIdx] = r2;
        }
        C.items.pop();
        C.remaining --;
        totalRemaining --;

        // 这里进行发奖：mint NFT / 发 ERC1155 / 记账
        // _mint(a.buyer, itemId);
        emit BoxOpened(a.buyer, pickedClass, itemId);
    }
}