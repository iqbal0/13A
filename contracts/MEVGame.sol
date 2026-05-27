// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MEVGame {
    uint256 public constant INITIAL_RESERVE_WETH = 10 ether;
    uint256 public constant INITIAL_RESERVE_MEME = 1000000 ether;

    struct TargetTx {
        uint256 id;
        uint256 wethIn;
        uint256 minMemeOut;
        bool executed;
    }

    mapping(uint256 => TargetTx) public mempool;
    uint256 public nextTxId;

    address[] public players;
    mapping(address => bool) public isPlayer;
    mapping(address => uint256) public playerScores;
    mapping(address => mapping(uint256 => bool)) public hasSolved;

    function getPlayers() external view returns (address[] memory) {
        return players;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function createRandomTx() external {
        uint256 wethIn = 0.1 ether + (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % 1 ether);
        uint256 expectedMeme = getAmountOut(wethIn, INITIAL_RESERVE_WETH, INITIAL_RESERVE_MEME);
        uint256 minMemeOut = expectedMeme * 90 / 100; // 10% slippage tolerance

        mempool[nextTxId] = TargetTx({
            id: nextTxId,
            wethIn: wethIn,
            minMemeOut: minMemeOut,
            executed: false
        });
        nextTxId++;
    }

    function simulateSandwich(uint256 txId, uint256 frontrunWethIn) external view returns (int256 profit) {
        TargetTx memory target = mempool[txId];
        require(!target.executed, "Already executed");

        uint256 resWeth = INITIAL_RESERVE_WETH;
        uint256 resMeme = INITIAL_RESERVE_MEME;

        // 1. Frontrun
        uint256 frontrunMemeOut = getAmountOut(frontrunWethIn, resWeth, resMeme);
        resWeth += frontrunWethIn;
        resMeme -= frontrunMemeOut;

        // 2. Target Tx
        uint256 targetMemeOut = getAmountOut(target.wethIn, resWeth, resMeme);
        require(targetMemeOut >= target.minMemeOut, "Target tx reverted: slippage");
        resWeth += target.wethIn;
        resMeme -= targetMemeOut;

        // 3. Backrun
        uint256 backrunWethOut = getAmountOut(frontrunMemeOut, resMeme, resWeth);
        
        return int256(backrunWethOut) - int256(frontrunWethIn);
    }

    function executeSandwich(uint256 txId, uint256 frontrunWethIn) external {
        TargetTx storage target = mempool[txId];
        require(!target.executed, "Already executed");
        require(!hasSolved[msg.sender][txId], "Already solved");

        uint256 resWeth = INITIAL_RESERVE_WETH;
        uint256 resMeme = INITIAL_RESERVE_MEME;

        // 1. Frontrun
        uint256 frontrunMemeOut = getAmountOut(frontrunWethIn, resWeth, resMeme);
        resWeth += frontrunWethIn;
        resMeme -= frontrunMemeOut;

        // 2. Target Tx
        uint256 targetMemeOut = getAmountOut(target.wethIn, resWeth, resMeme);
        require(targetMemeOut >= target.minMemeOut, "Target tx reverted: slippage");
        resWeth += target.wethIn;
        resMeme -= targetMemeOut;

        // 3. Backrun
        uint256 backrunWethOut = getAmountOut(frontrunMemeOut, resMeme, resWeth);
        
        int256 profit = int256(backrunWethOut) - int256(frontrunWethIn);
        require(profit > 0, "No profit");

        target.executed = true;
        hasSolved[msg.sender][txId] = true;
        
        if (!isPlayer[msg.sender]) {
            isPlayer[msg.sender] = true;
            players.push(msg.sender);
        }
        
        playerScores[msg.sender] += uint256(profit);
    }
}
