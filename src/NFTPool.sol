// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import "./interface/INFTPool.sol";
import {VaultNFT, WithdrawNFT} from "./struct/Struct.sol";

contract NFTPool is INFTPool, Ownable2Step, ReentrancyGuard {
    //存储NFT奖池
    VaultNFT[] public vaultNfts;

    mapping(address => mapping(uint256 => bool)) public isInPool;
    mapping(address => mapping(uint256 => address)) public userListOfPrizes;
    address public governor;
    uint256 public totalNfts;

    constructor() Ownable(msg.sender) {
        governor = msg.sender;
        totalNfts = 0;
    }

    modifier onlyGovernor() {
        if (msg.sender != governor) {
            revert NoGovernor();
        }
        _;
    }

    /**
     * 存入池子NFT
     * @param vaultNft NFT信息
     */
    function depositeNFT(VaultNFT memory vaultNft) external onlyGovernor {
        IERC721(vaultNft.collection).safeTransferFrom(
            msg.sender,
            address(this),
            vaultNft.tokenId
        );
        vaultNfts.push(
            VaultNFT({
                collection: vaultNft.collection,
                tokenId: vaultNft.tokenId,
                weight: vaultNft.weight,
                claimed: false
            })
        );
        totalNfts += 1;
        isInPool[vaultNft.collection][vaultNft.tokenId] = true;
        emit DepositeNFT(vaultNft.collection, vaultNft.tokenId);
    }

    function withdrawNFT(
        uint256 index,
        WithdrawNFT memory withdrawNft
    ) external nonReentrant {
        address prizesOwner = userListOfPrizes[withdrawNft.collection][
            withdrawNft.tokenId
        ];
        if (prizesOwner == address(0) || prizesOwner != msg.sender) {
            revert NotBelongToUser();
        }
        isInPool[withdrawNft.collection][withdrawNft.tokenId] = false;
        VaultNFT storage nft = vaultNfts[index];
        nft.claimed = true;
        IERC721(withdrawNft.collection).safeTransferFrom(
            address(this),
            msg.sender,
            withdrawNft.tokenId
        );
        emit WithdrawNFTPrize(
            withdrawNft.collection,
            withdrawNft.tokenId,
            msg.sender
        );
    }

    function prizeDistribution(address winner,address collection,uint256 tokenId)
    external
    onlyGovernor
    {
        userListOfPrizes[collection][tokenId] = winner;
        emit WinningPrize(winner,collection,tokenId);
    }
}
