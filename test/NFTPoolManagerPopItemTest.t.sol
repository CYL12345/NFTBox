// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/NFTPoolManager.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// 测试用NFT合约
contract TestNFT is ERC721 {
    constructor() ERC721("TestNFT", "TNFT") {}
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

// 主测试合约
contract NFTPoolManagerPopItemTest is Test {
    NFTPoolManager public poolManager;
    TestNFT public testNFT;
    address public alice;
    address public bob;
    address public authorizedCaller; // 授权调用者
    address public unauthorizedCaller; // 未授权调用者

    function setUp() public {
        // 创建测试账户
        alice = makeAddr("Alice");
        bob = makeAddr("Bob");
        authorizedCaller = makeAddr("AuthorizedCaller");
        unauthorizedCaller = makeAddr("UnauthorizedCaller");

        // 部署合约
        poolManager = new NFTPoolManager();
        testNFT = new TestNFT();

        // 给Alice mint 5个NFT
        for (uint256 i = 1; i <= 5; i++) {
            testNFT.mint(alice, i);
        }

        // Alice授权poolManager操作她的NFT
        vm.prank(alice);
        testNFT.setApprovalForAll(address(poolManager), true);

        // 管理员授权authorizedCaller调用popItem
        vm.prank(poolManager.owner());
        poolManager.setAuthorizedCaller(authorizedCaller, true);
    }

    // 辅助函数：向池中存入NFT
    function depositNFT(uint256 tokenId, uint8 rarity) internal {
        bytes memory data = abi.encodePacked(rarity); // 1字节编码
        vm.prank(alice);
        testNFT.safeTransferFrom(alice, address(poolManager), tokenId, data);
    }

    // ------------------------------
    // popItem测试用例
    // ------------------------------

    // 测试用例1：正常提取（从非空池提取）
    function test_PopItem_Success() public {
        // 1. 准备：向稀有度1的池存入3个NFT
        depositNFT(1, 1);
        depositNFT(2, 1);
        depositNFT(3, 1);
        assertEq(poolManager.poolLength(1), 3, unicode"初始池长度应为3");

        // 2. 记录提取前的NFT所有者（应为poolManager）
        assertEq(testNFT.ownerOf(2), address(poolManager), unicode"NFT应在池中");

        // 3. 授权调用者提取（randomness=5，预期索引=5%3=2）
        vm.prank(authorizedCaller);
        (address token, uint256 tokenId) = poolManager.popItem(1, 5, bob);

        // 4. 验证返回值
        assertEq(token, address(testNFT), unicode"返回的NFT合约地址错误");
        assertEq(tokenId, 3, unicode"提取的tokenId错误（应为索引2的NFT）");

        // 5. 验证池状态变化
        assertEq(poolManager.poolLength(1), 2, unicode"提取后池长度应为2");
        assertEq(poolManager.isInpool(address(testNFT), 3, 1), false, unicode"提取的NFT应从池中移除");
        assertEq(poolManager.isInpool(address(testNFT), 2, 1), true, unicode"剩余NFT应仍在池中");

        // 6. 验证NFT所有权已转移给bob
        assertEq(testNFT.ownerOf(3), bob, unicode"NFT应转移给接收者");


    }

    // 测试用例2：提取最后一个NFT（池变为空）
    function test_PopItem_Success_EmptyPoolAfter() public {
        // 1. 存入1个NFT
        depositNFT(1, 2);
        assertEq(poolManager.poolLength(2), 1, unicode"初始池长度应为1");

        // 2. 提取
        vm.prank(authorizedCaller);
        poolManager.popItem(2, 0, bob);

        // 3. 验证池为空
        assertEq(poolManager.poolLength(2), 0, unicode"提取后池应为空");
        assertEq(poolManager.isInpool(address(testNFT), 1, 2), false, unicode"池中不应有NFT");
    }

    // 测试用例3：失败场景（从空池提取）
    function test_PopItem_Fail_EmptyPool() public {
        // 稀有度3的池为空
        assertEq(poolManager.poolLength(3), 0, unicode"池初始应为空");

        // 预期提取失败，触发ErrorPool
        vm.prank(authorizedCaller);
        poolManager.popItem(3, 100, bob);
    }

    // 测试用例4：失败场景（未授权调用者）
    function test_PopItem_Fail_Unauthorized() public {
        // 存入NFT

        depositNFT(1, 1);

        // 未授权调用者尝试提取，预期触发NoCaller
        vm.prank(unauthorizedCaller);
        poolManager.popItem(1, 0, bob);
    }

    // 测试用例5：失败场景（随机数越界，但模运算自动处理）
    function test_PopItem_Success_RandomnessLargerThanLength() public {
        // 存入2个NFT（长度=2）
        depositNFT(1, 4);
        depositNFT(2, 4);

        // 随机数=100，100%2=0（提取索引0的NFT）
        vm.prank(authorizedCaller);
        (, uint256 tokenId) = poolManager.popItem(4, 100, bob);
        assertEq(tokenId, 1, unicode"应提取索引0的NFT");
    }

    // 测试用例6：验证swap-and-pop逻辑（提取中间元素后，最后元素补位）
    function test_PopItem_SwapAndPop() public {
        // 存入3个NFT（索引0:1, 索引1:2, 索引2:3）
        depositNFT(1, 1);
        depositNFT(2, 1);
        depositNFT(3, 1);

        // 提取索引1的NFT（randomness=1，1%3=1）
        vm.prank(authorizedCaller);
        poolManager.popItem(1, 1, bob);

        // 验证池状态：最后元素（3）应补位到索引1
        (address token, uint256 id) = poolManager.itemAt(1, 1);
        assertEq(token, address(testNFT), unicode"补位NFT合约错误");
        assertEq(id, 3, unicode"补位NFT ID错误");
    }
}
