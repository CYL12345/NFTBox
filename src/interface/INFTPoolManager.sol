// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "../NFTPoolManager.sol";
interface INFTPoolManager{
    function popItem(
        uint8 rarity,
        uint256 randomness,
        address to
    )external returns(address token,uint256 tokenId);
}