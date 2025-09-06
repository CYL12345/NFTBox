// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// 定义消费者合约需要实现的接口
interface IRandomConsumer {
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;
}

/**
 * 一个简单的随机数协调器合约
 * 功能：生成requestId，接收随机数请求，并自动触发回调
 */
contract SimpleRandomCoordinator {
    uint256 private _nextRequestId = 1; // 自增的请求ID
    mapping(uint256 => IRandomConsumer) private _requests; // 记录请求对应的消费者合约

    // 事件：当新的随机数请求被创建时触发
    event RequestCreated(uint256 indexed requestId, address indexed consumer);
    // 事件：当随机数回调完成时触发
    event RandomFulfilled(uint256 indexed requestId, uint256[] randomWords);

    /**
     * 发起随机数请求
     * @param consumer 需要接收随机数的合约地址
     * @param numWords 需要生成的随机数数量
     * @return requestId 生成的请求ID
     */
    function requestRandomWords(address consumer, uint32 numWords) external returns (uint256 requestId) {
        require(consumer != address(0), "无效的消费者合约地址");
        require(numWords > 0, "随机数数量必须大于0");

        // 生成新的请求ID
        requestId = _nextRequestId++;
        _requests[requestId] = IRandomConsumer(consumer);

        // 触发请求创建事件
        emit RequestCreated(requestId, consumer);

        // 生成随机数并立即回调（实际场景中可能会有延迟）
        uint256[] memory randomWords = _generateRandomWords(numWords, requestId);
        _fulfillRandomWords(requestId, randomWords);

        return requestId;
    }

    /**
     * 生成随机数
     * 注意：这只是一个简单的模拟实现，实际应用中应使用Chainlink VRF等安全的随机数源
     */
    function _generateRandomWords(uint32 numWords, uint256 requestId) private view returns (uint256[] memory) {
        uint256[] memory randomWords = new uint256[](numWords);
        
        for (uint32 i = 0; i < numWords; i++) {
            // 基于区块信息和请求ID生成伪随机数
            randomWords[i] = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                msg.sender,
                requestId,
                i
            )));
        }
        
        return randomWords;
    }

    /**
     * 触发随机数回调
     */
    function _fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) private {
        IRandomConsumer consumer = _requests[requestId];
        require(address(consumer) != address(0), "无效的请求ID");

        // 调用消费者合约的回调函数
        consumer.fulfillRandomWords(requestId, randomWords);
        
        // 触发回调完成事件
        emit RandomFulfilled(requestId, randomWords);
        
        // 清理请求记录
        delete _requests[requestId];
    }

    /**
     * 手动触发指定请求的回调（用于测试）
     */
    function manualFulfill(uint256 requestId, uint32 numWords) external returns (uint256[] memory) {
        require(_requests[requestId] != IRandomConsumer(address(0)), "请求ID不存在");
        
        uint256[] memory randomWords = _generateRandomWords(numWords, requestId);
        _fulfillRandomWords(requestId, randomWords);
        
        return randomWords;
    }
}

// 示例消费者合约（如何使用上面的随机数协调器）
contract RandomConsumerExample is IRandomConsumer {
    SimpleRandomCoordinator public coordinator;
    mapping(uint256 => uint256[]) public requestIdToRandomWords; // 存储请求对应的随机数

    event RandomReceived(uint256 indexed requestId, uint256[] randomWords);

    constructor(address coordinatorAddress) {
        coordinator = SimpleRandomCoordinator(coordinatorAddress);
    }

    // 发起随机数请求
    function requestRandom() external returns (uint256) {
        return coordinator.requestRandomWords(address(this), 1); // 请求1个随机数
    }

    // 实现回调函数
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external override {
        // 验证调用者是否为协调器合约
        require(msg.sender == address(coordinator), "只能由协调器调用");
        
        requestIdToRandomWords[requestId] = randomWords;
        emit RandomReceived(requestId, randomWords);
    }
}
