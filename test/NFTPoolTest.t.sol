// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/NFTPool.sol";
import "../src/struct/Struct.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

// 部署一个测试用的ERC721合约
contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    // 简化铸造功能，方便测试
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract NFTPoolTest is Test {
    NFTPool public nftPool;
    MockNFT public mockNFT;
    address public governor = address(0x1); // 管理者地址
    address public user = address(0x2);    // 普通用户地址
    address public stranger = address(0x3); // 陌生人地址

    uint256 public constant TEST_TOKEN_ID = 1; // 测试用的NFT ID

    function setUp() public {
        // 部署测试合约
        nftPool = new NFTPool();
        mockNFT = new MockNFT();

        // 初始化：将管理者设置为governor（NFTPool构造函数已处理）
        vm.prank(governor); // 模拟governor操作

        // 给governor铸造一个测试NFT
        mockNFT.mint(governor, TEST_TOKEN_ID);
    }

    // 测试1：管理者存入NFT到奖池
    function test_DepositeNFT_OnlyGovernor() public {
        vm.prank(governor); // 以管理者身份操作
        
        // 授权合约转移NFT
        mockNFT.approve(address(nftPool), TEST_TOKEN_ID);

        // 构造存入的NFT信息
        VaultNFT memory vaultNft = VaultNFT({
            collection: address(mockNFT),
            tokenId: TEST_TOKEN_ID,
            weight: 100, // 权重测试值
            claimed: false
        });

        // 执行存入操作
        nftPool.depositeNFT(vaultNft);

        // 验证状态变化
        assertEq(nftPool.totalNfts(), 1); // 总数量应为1
        assertEq(nftPool.isInPool(address(mockNFT), TEST_TOKEN_ID), true); // 标记为在池中
        assertEq(mockNFT.ownerOf(TEST_TOKEN_ID), address(nftPool)); // 合约应持有NFT

        // 验证事件
    }

    // 测试2：非管理者存入NFT应失败
    function test_DepositeNFT_RevertIfNotGovernor() public {
        vm.prank(stranger); // 以陌生人身份操作
        VaultNFT memory vaultNft = VaultNFT({
            collection: address(mockNFT),
            tokenId: TEST_TOKEN_ID,
            weight: 100,
            claimed: false
        });

        // 预期失败：非管理者调用
        vm.expectRevert(INFTPool.NoGovernor.selector);
        nftPool.depositeNFT(vaultNft);
    }

    // 测试3：管理者分配奖品给用户
    function test_PrizeDistribution() public {
        // 先存入NFT到奖池
        vm.prank(governor);
        mockNFT.approve(address(nftPool), TEST_TOKEN_ID);
        nftPool.depositeNFT(VaultNFT({
            collection: address(mockNFT),
            tokenId: TEST_TOKEN_ID,
            weight: 100,
            claimed: false
        }));

        // 分配奖品给user
        vm.prank(governor);
        nftPool.prizeDistribution(user, address(mockNFT), TEST_TOKEN_ID);

        // 验证分配结果
        assertEq(nftPool.userListOfPrizes(address(mockNFT), TEST_TOKEN_ID), user);

        // 验证事件
    }

    // 测试4：获奖者提取NFT
    function test_WithdrawNFT_Success() public {
        // 1. 存入NFT
        vm.prank(governor);
        mockNFT.approve(address(nftPool), TEST_TOKEN_ID);
        nftPool.depositeNFT(VaultNFT({
            collection: address(mockNFT),
            tokenId: TEST_TOKEN_ID,
            weight: 100,
            claimed: false
        }));

        // 2. 分配给user
        vm.prank(governor);
        nftPool.prizeDistribution(user, address(mockNFT), TEST_TOKEN_ID);

        // 3. 用户提取NFT
        vm.prank(user);
        WithdrawNFT memory withdrawNft = WithdrawNFT({
            collection: address(mockNFT),
            tokenId: TEST_TOKEN_ID
        });
        nftPool.withdrawNFT(0, withdrawNft); // index=0（第一个存入的NFT）

        // 验证状态变化
        assertEq(nftPool.isInPool(address(mockNFT), TEST_TOKEN_ID), false); // 已移出池
        assertEq(mockNFT.ownerOf(TEST_TOKEN_ID), user); // 用户应持有NFT


    }

    // 测试5：非获奖者提取NFT应失败
    function test_WithdrawNFT_RevertIfNotOwner() public {
        // 1. 存入并分配给user
        vm.prank(governor);
        mockNFT.approve(address(nftPool), TEST_TOKEN_ID);
        nftPool.depositeNFT(VaultNFT({
            collection: address(mockNFT),
            tokenId: TEST_TOKEN_ID,
            weight: 100,
            claimed: false
        }));
        vm.prank(governor);
        nftPool.prizeDistribution(user, address(mockNFT), TEST_TOKEN_ID);

        // 2. 陌生人尝试提取
        vm.prank(stranger);
        WithdrawNFT memory withdrawNft = WithdrawNFT({
            collection: address(mockNFT),
            tokenId: TEST_TOKEN_ID
        });

        // 预期失败：非奖品所有者
        vm.expectRevert(INFTPool.NotBelongToUser.selector);
        nftPool.withdrawNFT(0, withdrawNft);
    }

    // 测试6：验证onlyGovernor修饰符
    function test_OnlyGovernor_Modifier() public {
        // 陌生人尝试调用仅管理者功能
        vm.prank(stranger);
        vm.expectRevert(INFTPool.NoGovernor.selector);
        nftPool.prizeDistribution(user, address(mockNFT), TEST_TOKEN_ID);
    }
}
