// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface INexusStaking {
    function distributeReward(address token, uint256 _amount) external payable;
}