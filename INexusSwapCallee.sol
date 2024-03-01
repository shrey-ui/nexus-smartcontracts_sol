// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface INexusSwapCallee {
    function NexusSwapCall(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external;
}
