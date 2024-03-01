// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface INexusNFTWeight {
    function nexusNFTWeight(uint256 tokenId) external view returns (uint256);
}