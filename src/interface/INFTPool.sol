// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface INFTPool {

    error NoGovernor();//非管理者
    error NotBelongToUser();//非奖品拥有者
    event DepositeNFT(address collection,uint256 tokenId);
    event WithdrawNFTPrize(address collection,uint256 tokenId,address to);
    event WinningPrize(address winner,address collection,uint256 tokenId);
}