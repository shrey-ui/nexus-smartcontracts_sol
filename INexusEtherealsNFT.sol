// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

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
