// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";

contract NexusNFTWeight is Ownable {
    mapping(uint256 => uint256) public nexusNFTWeight;

    function setNexusNFTWeight(
        uint256 _tokenId,
        uint256 _weight
    ) external onlyOwner {
        nexusNFTWeight[_tokenId] = _weight;
    }
}
