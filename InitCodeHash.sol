// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import '../NexusSwap/NexusSwapPair.sol';

contract CalHash {
    function getInitHash() public pure returns(bytes32){
        bytes memory bytecode = type(NexusSwapPair).creationCode;
        return keccak256(abi.encodePacked(bytecode));
    }
}