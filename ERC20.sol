// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MyNToken is ERC20 {
    address public owner;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        owner = msg.sender;
    }
}
