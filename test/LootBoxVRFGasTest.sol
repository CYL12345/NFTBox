// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/LotBoxVRF.sol"; // 替换为你的合约实际路径;
import "lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

// 测试合约：模拟 VRF Coordinator 行为（避免依赖真实链上节点）
contract MockVRFCoordinatorV2Plus is IVRFCoordinatorV2Plus {
    uint256 public nextRequestId = 1;
    LootBoxVRF public lootBox;

    // 初始化：绑定待测试的 LootBox 合约
    constructor(address _lootBox) {
        lootBox = LootBoxVRF(_lootBox);
    }

    // 模拟发起随机数请求：返回自增的 requestId
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata) 
        external 
        returns (uint256 requestId) 
    {
        requestId = nextRequestId++;
        return requestId;
    }

    // 模拟 VRF 节点回调：触发 LootBox 的 fulfillRandomWords
    function mockFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        lootBox.fulfillRandomWords(requestId, randomWords);
    }

    // 以下为 IVRFCoordinatorV2Plus 接口的空实现（测试无需实际逻辑）
    function createSubscription() external returns (uint64) { return 0; }
    function fundSubscription(uint64, uint256) external payable {}
    function addConsumer(uint64, address) external {}
    function removeConsumer(uint64, address) external {}
    function cancelSubscription(uint64, address) external returns (uint256) { return 0; }
    function getSubscription(uint64) external view returns (uint96, uint64, address, address[] memory) {
        address[] memory consumers = new address[](0);
        return (0, 0, address(0), consumers);
    }
    function requestRandomWordsWithConsumer(VRFV2PlusClient.RandomWordsRequest calldata, address) 
        external 
        returns (uint256) 
    {
        return 0;
    }
}

// 核心 Gas 测试合约
contract LootBoxVRFGasTest is Test {
    LootBoxVRF public lootBox;
    MockVRFCoordinatorV2Plus public mockCoordinator;
    address public owner = address(0x1); // 测试用账户
    address public user1 = address(0x2); // 模拟用户
    uint256 public testSubId = 123; // 测试用订阅 ID（无需真实有效）

    // 初始化：部署合约 + 模拟 VRF Coordinator + 初始化盲盒奖品池
    function setUp() public {
        // 部署 LootBox 合约
        vm.startPrank(owner);
        lootBox = new LootBoxVRF(testSubId);
        
        // 部署模拟 VRF Coordinator，并让 LootBox 指向它（替换原 coordinator 地址）
        mockCoordinator = new MockVRFCoordinatorV2Plus(address(lootBox));
        vm.etch(lootBox.vrfCoordinator(), address(mockCoordinator).code); // 替换合约代码实现
        
        // 初始化盲盒奖品池（4个稀有度：SSR[1个]、SR[2个]、R[3个]、N[4个]）
        _initLootBoxPools();
        vm.stopPrank();
    }

    // 辅助函数：初始化盲盒奖品池（填充 Class 结构体数据）
    function _initLootBoxPools() private {
        // 注意：由于 Class 中的 idex 是 mapping，需通过合约内函数初始化（此处用 vm.store 直接操作存储）
        uint256 classCount = 4; // SSR(0)、SR(1)、R(2)、N(3)
        
        for (uint8 i = 0; i < classCount; i++) {
            // 为每个稀有度设置奖品数量和 ID（如 SSR：[1001]，SR：[2001,2002] 等）
            uint256[] memory itemIds;
            if (i == 0) itemIds = new uint256[](1); // SSR：1个奖品
            else if (i == 1) itemIds = new uint256[](2); // SR：2个奖品
            else if (i == 2) itemIds = new uint256[](3); // R：3个奖品
            else itemIds = new uint256[](4); // N：4个奖品
            
            // 填充奖品 ID（按稀有度区分）
            for (uint256 j = 0; j < itemIds.length; j++) {
                itemIds[j] = (i + 1) * 1000 + (j + 1); // 1001(SSR)、2001(SR)、3001(R)、4001(N)
            }
            
            // 1. 存储 Class.items 数组
            bytes32 itemsSlot = keccak256(abi.encode(i, keccak256("classes"))) + 0; // Class.items 的存储槽
            for (uint256 j = 0; j < itemIds.length; j++) {
                vm.store(address(lootBox), bytes32(uint256(itemsSlot) + j), bytes32(itemIds[j]));
            }
            
            // 2. 存储 Class.idex 映射（itemId -> 索引）
            for (uint256 j = 0; j < itemIds.length; j++) {
                bytes32 idexSlot = keccak256(abi.encode(itemIds[j], keccak256(abi.encode(i, keccak256("classes"))) + 1));
                vm.store(address(lootBox), idexSlot, bytes32(j));
            }
            
            // 3. 存储 Class.remaining（剩余数量 = 数组长度）
            bytes32 remainingSlot = keccak256(abi.encode(i, keccak256("classes"))) + 2;
            vm.store(address(lootBox), remainingSlot, bytes32(itemIds.length));
            
            // 4. 更新 totalRemaining（总剩余数量）
            lootBox.totalRemaining() += itemIds.length;
        }
    }

    // ------------------------------ Gas 测试用例 ------------------------------
    /**
     * 测试 1：buyBox 函数 Gas 消耗（发起随机数请求）
     * 场景：用户购买盲盒，触发 requestRandomWords 并记录请求状态
     */
    function testGas_buyBox() public {
        vm.startPrank(user1);
        
        // 记录 Gas 消耗（使用 forge-std 的 gasLeft() 函数）
        uint256 gasBefore = gasleft();
        lootBox.buyBox(); // 发起购买（无需传 msg.value，原合约中价格判断已注释）
        uint256 gasUsed = gasBefore - gasleft();
        
        // 打印 Gas 消耗（运行时通过 forge test -vv 查看）
        console.log("Gas used for buyBox (request random words):", gasUsed);
        
        vm.stopPrank();
    }

    /**
     * 测试 2：fulfillRandomWords 函数 Gas 消耗（回调处理 + 奖品抽取）
     * 场景：模拟 VRF 回调，触发奖品抽取（swap-and-pop 逻辑）
     */
    function testGas_fulfillRandomWords() public {
        vm.startPrank(user1);
        
        // 1. 先发起购买，获取 requestId
        uint256 requestId = lootBox.buyBox();
        vm.stopPrank();
        
        // 2. 模拟 VRF 回调，计算 Gas 消耗
        vm.startPrank(address(mockCoordinator)); // 模拟 Coordinator 触发回调
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123456789; // 随机数示例
        
        uint256 gasBefore = gasleft();
        mockCoordinator.mockFulfillRandomWords(requestId, randomWords); // 触发回调
        uint256 gasUsed = gasBefore - gasleft();
        
        // 打印 Gas 消耗
        console.log("Gas used for fulfillRandomWords (callback + draw):", gasUsed);
        console.log("Current callbackGasLimit:", lootBox.callbackGasLimit());
        console.log("Is gas used within limit?", gasUsed <= lootBox.callbackGasLimit());
        
        vm.stopPrank();
    }

    /**
     * 测试 3：多次购买 + 回调的 Gas 消耗变化
     * 场景：模拟 5 次购买+回调，观察 Gas 消耗是否稳定（避免状态累积导致 Gas 激增）
     */
    function testGas_multipleBuyAndFulfill() public {
        vm.startPrank(user1);
        
        // 循环 5 次购买+回调
        for (uint8 i = 0; i < 5; i++) {
            // 1. 购买盲盒
            uint256 requestId = lootBox.buyBox();
            vm.stopPrank();
            
            // 2. 模拟回调并计算 Gas
            vm.startPrank(address(mockCoordinator));
            uint256[] memory randomWords = new uint256[](1);
            randomWords[0] = uint256(keccak256(abi.encode(i, block.timestamp))); // 每次不同的随机数
            
            uint256 gasBefore = gasleft();
            mockCoordinator.mockFulfillRandomWords(requestId, randomWords);
            uint256 gasUsed = gasBefore - gasleft();
            
            // 打印每次的 Gas 消耗
            console.log(string(abi.encodePacked("Round ", vm.toString(i+1), " - fulfillGasUsed:")), gasUsed);
            vm.stopPrank();
            vm.startPrank(user1);
        }
        
        vm.stopPrank();
    }

    /**
     * 测试 4：不同回调 Gas 限制的兼容性
     * 场景：修改 callbackGasLimit 为 150000（低于默认 200000），验证是否触发 revert
     */
    function testGas_lowCallbackGasLimitRevert() public {
        vm.startPrank(owner);
        // 尝试将 Gas 限制设为 150000（低于合约内 200000 的最小值限制）
        vm.expectRevert(lootBox.gatLimitTooLow.selector); // 预期触发 "gasLimitTooLow" revert
        lootBox.updateCallbackGasLimit(150000);
        vm.stopPrank();
        
        // 验证设置 200000 是允许的
        vm.prank(owner);
        lootBox.updateCallbackGasLimit(200000);
        assertEq(lootBox.callbackGasLimit(), 200000);
    }
}