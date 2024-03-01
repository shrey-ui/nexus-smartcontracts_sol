// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./NexusSwap/Interfaces/INexusSwapFactory.sol";
import "./NexusSwap/NexusSwapPair.sol";

contract NexusFactory is INexusSwapFactory {
    address public override feeTo;
    address public override feeToSetter;
    address public override migrator;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view override returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(NexusSwapPair).creationCode);
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external override returns (address pair) {
        require(tokenA != tokenB, "NEXUS: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "NEXUS: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "NEXUS: PAIR_EXISTS"); // single check is sufficient
        bytes memory bytecode = type(NexusSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        NexusSwapPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "NEXUS: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setMigrator(address _migrator) external override {
        require(msg.sender == feeToSetter, "NEXUS: FORBIDDEN");
        migrator = _migrator;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "NEXUS: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
