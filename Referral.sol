// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

interface INexusEtherealsNFT {
    function cost() external view returns (uint256);

    function whitelistDiscount() external view returns (uint256);

    function whitelistEnabled() external view returns (bool);

    function totalSupply() external view returns (uint256);

    function isWhitelisted(address _address) external view returns (bool);

    function mint(uint256 _mintAmount) external payable;

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

contract NFTReferral is IERC721Receiver {
    address public nexusNFT;

    event ReferralUsed(
        address indexed referrer,
        address indexed buyer,
        uint256 amount
    );

    constructor(address _nexusNFT) {
        nexusNFT = _nexusNFT;
    }

    function mintNFT(
        uint256 _mintamount,
        address _referrerAddress
    ) public payable {
        INexusEtherealsNFT NFT = INexusEtherealsNFT(nexusNFT);
        uint256 originPrice = NFT.cost();
        uint256 discountPrice;
        require(msg.value >= originPrice * _mintamount, "Not Enough Fund");

        if (NFT.isWhitelisted(address(this)) && NFT.whitelistEnabled())
            discountPrice = NFT.whitelistDiscount();

        uint256 mintPrice = originPrice - discountPrice;

        uint256 curTokenSupply = NFT.totalSupply();

        NFT.mint{value: mintPrice * _mintamount}(_mintamount);
        for (uint256 i = 1; i <= _mintamount; i++) {
            NFT.transferFrom(
                address(this),
                msg.sender,
                curTokenSupply + i
            );
        }
        uint256 reward = msg.value - mintPrice * _mintamount;
        if (reward > 0) {
            (bool os, ) = payable(_referrerAddress).call{value: reward}("");
            require(os);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
