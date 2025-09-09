// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/NFTPoolManager.sol"; // 引入你的NFTPoolManager合约（路径需根据实际项目调整）
import "@openzeppelin/contracts/token/ERC721/ERC721.sol"; // 引入OpenZeppelin的ERC721实现


// ------------------------------
// 测试工具：模拟实际NFT合约（带mint功能）
// ------------------------------
contract TestNFT is ERC721 {
    constructor() ERC721("TestNFT", "TNFT") {}

    // 公开mint函数，方便测试时生成NFT
    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}


// ------------------------------
// 主测试合约：测试NFTPoolManager的onERC721Received回调
// ------------------------------
contract NFTPoolManagerTest is Test {
    // 测试中用到的合约实例
    NFTPoolManager public poolManager; // 待测试的池管理合约
    TestNFT public testNFT;           // 测试用NFT合约
    address public alice;             // 测试用户（NFT持有者）
    address public bob;               // 测试用户（备用）

    // ------------------------------
    // 测试前置初始化（每个测试用例执行前都会运行）
    // ------------------------------
    function setUp() public {
        // 1. 部署合约
        poolManager = new NFTPoolManager();
        testNFT = new TestNFT();

        // 2. 创建测试账户（使用Forge的prank功能模拟不同地址）
        alice = makeAddr("Alice"); // 生成名为"Alice"的测试地址
        bob = makeAddr("Bob");     // 生成名为"Bob"的测试地址

        // 3. 给Alice mint 5个NFT，用于后续转账测试
        for(uint256 i=1;i<=5;i++){
            testNFT.mint(alice,i);
        }
        // 4. Alice授权poolManager合约操作她的NFT（因为safeTransferFrom需要授权）
        vm.prank(alice); // 模拟Alice调用
        testNFT.setApprovalForAll(address(poolManager), true);
    }

    // ------------------------------
    // 测试用例1：正常存入（data长度=1字节，稀有度=1）
    // ------------------------------
    function test_OnERC721Received_Success_DataLength1() public {
        // 1. 准备参数：data为1字节（稀有度=1，编码为uint8）
        bytes memory data = abi.encodePacked(uint8(1)); // 1字节编码
        uint256 tokenId = 1;

        // 2. 模拟Alice调用testNFT的safeTransferFrom，将NFT转入poolManager
        vm.prank(alice); // 切换为Alice的上下文
        testNFT.safeTransferFrom(alice, address(poolManager), tokenId, data);

        // 3. 验证结果：检查NFT是否成功存入对应稀有度池
        // 3.1 验证池长度（稀有度1的池应包含1个NFT）
        assertEq(poolManager.poolLength(1), 1, "Pool length should be 1");
        // 3.2 验证池内NFT信息（索引0应为testNFT合约地址+tokenId=1）
        (address storedToken, uint256 storedTokenId) = poolManager.itemAt(1, 0);
        assertEq(storedToken, address(testNFT), "Stored NFT contract mismatch");
        assertEq(storedTokenId, tokenId, "Stored tokenId mismatch");
        // 3.3 验证索引映射（该NFT应被标记为"在池中"）
        assertEq(poolManager.isInpool(address(testNFT), tokenId, 1), true, "NFT should be in pool");

       
    }

    // ------------------------------
    // 测试用例2：正常存入（data长度=32字节，稀有度=4）
    // ------------------------------
    function test_OnERC721Received_Success_DataLength32() public {
        // 1. 准备参数：data为32字节（稀有度=4，用abi.encode标准编码）
        bytes memory data = abi.encode(uint8(4)); // 32字节编码
        uint256 tokenId = 2;

        // 2. 模拟Alice转账NFT到poolManager
        vm.prank(alice);
        testNFT.safeTransferFrom(alice, address(poolManager), tokenId, data);

        // 3. 验证结果
        assertEq(poolManager.poolLength(4), 1, "Pool length should be 1");
        (address storedToken, uint256 storedTokenId) = poolManager.itemAt(4, 0);
        assertEq(storedToken, address(testNFT), "Stored NFT contract mismatch");
        assertEq(storedTokenId, tokenId, "Stored tokenId mismatch");
        assertEq(poolManager.isInpool(address(testNFT), tokenId, 4), true, "NFT should be in pool");
    }

    // ------------------------------
    // 测试用例3：失败场景（data长度=2字节，触发invalidData错误）
    // ------------------------------
    function test_OnERC721Received_Fail_InvalidDataLength() public {
        // 1. 准备参数：data长度=2字节（不符合合约要求的1/32字节）
        bytes memory data = abi.encodePacked(uint16(1)); // 2字节数据
        uint256 tokenId = 1;

        // 2. 预期调用失败，且revert原因是invalidData自定义错误
        vm.prank(alice);
        testNFT.safeTransferFrom(alice, address(poolManager), tokenId, data);

        // 3. 验证结果：NFT未存入池（池长度仍为0）
        assertEq(poolManager.poolLength(1), 0, "Pool length should remain 0");
    }

    // ------------------------------
    // 测试用例4：失败场景（稀有度=5，超出0-4范围）
    // ------------------------------
    function test_OnERC721Received_Fail_InvalidRarity() public {
        // 1. 准备参数：data长度=1字节，但稀有度=5（合约限制1-4）
        bytes memory data = abi.encodePacked(uint8(5)); // 稀有度超出范围
        uint256 tokenId = 1;

        // 2. 预期调用失败，revert原因是"Invalid rarity range"
        vm.prank(alice);
        vm.expectRevert("Invalid rarity range"); // 匹配require的字符串提示
        testNFT.safeTransferFrom(alice, address(poolManager), tokenId, data);

        // 3. 验证结果：NFT未存入池
        assertEq(poolManager.poolLength(5), 0, "Pool length should remain 0");
    }

    // ------------------------------
    // 测试用例5：失败场景（直接调用onERC721Received，触发权限异常）
    // ------------------------------
    function test_OnERC721Received_Fail_DirectCall() public {
        // 1. 直接调用onERC721Received（跳过NFT合约的safeTransferFrom）
        bytes memory data = abi.encodePacked(uint8(1));
        vm.expectRevert(); // 直接调用会导致msg.sender不是NFT合约，后续safeTransferFrom会失败
        poolManager.onERC721Received(alice, alice, 1, data);
    }


    function test_popItem_success() public {
        
    }
}