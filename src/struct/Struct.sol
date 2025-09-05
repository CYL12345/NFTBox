// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


enum PrizeType{NFT,ERC20,POINT}
struct VaultNFT{
    address collection; //合约地址
    uint256 tokenId; //合约Id
    uint256 weight; //抽奖权重或稀有度
    bool claimed; //是否已经被抽取
}

//积分奖励
struct VaultReward{
    address tokenAddress; //ERC20地址，可以为平台代币或积分
    uint256 amount; //数量
    uint256 weight;//权重
    bool claimed;//奖品状态
}

//抽奖结果
struct Prize{
    PrizeType prizeType;//中奖类型
    address tokenAddress;//ERC721地址或者ERC20代币
    uint256 tokenId;//tokenId 如中奖类型为ERC20，tokenId为0
    uint256 tokenAmount;//NFT数量为1或ERC20代币数量
    address PrizeOwner;//中奖者
}

struct WithdrawNFT{
    address collection; //合约地址
    uint256 tokenId; //合约Id
}
