//SPDX-License-Identifier
pragma solidity ^0.8.28;

import "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "../interface/INFTPoolManager.sol";
contract XYDBOX is ERC721Enumerable,VRFConsumerBaseV2Plus{

    INFTPoolManager public poolManager;
    //-----VRF配置-----
    IVRFCoordinatorV2Plus COORDINATOR;
    address private vrfCoordinator = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B; //合约地址
    bytes32 private keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae; //对应VRF配置的gaslane (费用配置)
    uint256 private subId;  //订阅号
    uint32 public  callbackGasLimit = 200000;//回调时候的最大gas费用
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 1;

    //-----盲盒配置-----
    uint256 public boxTotalSupply = 1;
    uint256 public boxPrice = 0.001 ether;

    mapping(uint256 => bool) public ravealed;//是否开盒
    mapping(uint256 => uint8) public rarity;//稀有度
    mapping(uint256 => uint256) private boxRanNum;//盲盒随机数
    mapping(uint256 => uint256) public requestIdToBoxId;//requestID => tokenId
    mapping(uint256 => uint256) public boxIdToRequestId;//tokenId => requestId

    struct RarityConfig{
        uint8 rarityType;//稀有度编号
        uint16 probability;//百分比*100（1% = 100）
    }

    RarityConfig[] public rarityPool;
    uint16 public constant BASE = 10000;//100%

    error NotEnoughETH();
    error BoxRevealed();
    error NotOwner();
    event RandomsRequest(uint256 requestId,address indexed user);
    event OpenBox(address opener,uint8 pickedClass,address prizeAddress,uint256 prizeId);
    constructor(
        uint256 _subscriptionId
    ) ERC721("XYDBOX","XBX") VRFConsumerBaseV2Plus(vrfCoordinator){
        //配置稀有度
        rarityPool.push(RarityConfig(1,100));//1%SSR
        rarityPool.push(RarityConfig(2,900));//9%SR
        rarityPool.push(RarityConfig(3,3000));//30%SR
        rarityPool.push(RarityConfig(4,6000));//60%SR

        COORDINATOR = IVRFCoordinatorV2Plus(vrfCoordinator);
        subId = _subscriptionId;
    }
    
    function buyBox() external payable{
        if(msg.value < boxPrice){
            revert NotEnoughETH();
        }
        uint256 tokenId = boxTotalSupply++;
        _safeMint(msg.sender,tokenId);
        uint256 requestId = _requestRandomWords();
        requestIdToBoxId[requestId] = tokenId;
        boxIdToRequestId[tokenId] = requestId;
    }
    //开盒
    function openBox(uint256 tokenId) external{
        if(ravealed[tokenId]){
            revert BoxRevealed();
        }
        if(ownerOf(tokenId) != msg.sender){
            revert NotOwner();
        }
        uint8 pickedClass;
        ravealed[tokenId] = true;
        uint256 ranNum = boxRanNum[tokenId];
        uint256 r = ranNum % BASE;
        uint256 acc = 0;
        for(uint8 i=0;i<rarityPool.length;i++){
            acc += rarityPool[i].probability;
            if(r<acc){
                pickedClass = i;
                break;
            }
        }
        rarity[tokenId] = pickedClass;

        (address token,uint256 prizeNftId) = poolManager.popItem(pickedClass,ranNum,msg.sender);
        emit OpenBox(msg.sender,pickedClass,token,prizeNftId);
    } 

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    )internal override{
        uint256 tokenId = requestIdToBoxId[requestId];
        boxRanNum[tokenId] = randomWords[0];
    }
    function _requestRandomWords() internal returns(uint256){
        VRFV2PlusClient.RandomWordsRequest memory randomWordRequest = VRFV2PlusClient.RandomWordsRequest({
            keyHash:keyHash,
            subId:subId,
            requestConfirmations:requestConfirmations,
            callbackGasLimit:callbackGasLimit,
            numWords:numWords,
            extraArgs:VRFV2PlusClient._argsToBytes(
                VRFV2PlusClient.ExtraArgsV1({
                    nativePayment:true
                })
            )
        });
        uint256 requestId = COORDINATOR.requestRandomWords(randomWordRequest);
        emit RandomsRequest(requestId,msg.sender);
        return requestId;
    }

}