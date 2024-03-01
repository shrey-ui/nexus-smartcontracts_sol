// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DistributeNexus is Ownable {
    address public nexusToken;
    address public multiStaking;
    uint256 public distAmount;
    uint256 public lastDistribution;
    uint256 public timeInterval;
    uint256 public nextDistribution;

    function setnexusToken(address _nexusToken) public onlyOwner {
        nexusToken = _nexusToken;
    }

    function setMultiStaking(address _multiStaking) public onlyOwner {
        multiStaking = _multiStaking;
    }

    function setDistAmount(uint256 _distAmount) public onlyOwner {
        distAmount = _distAmount;
    }

    function setTimeInterval(uint256 _timeInterval) public onlyOwner{
        timeInterval = _timeInterval;
    }

    function distribute() public {
        require(block.timestamp >= nextDistribution, "Distribution not available");
        IERC20 token = IERC20(nexusToken);
        token.transfer(multiStaking, distAmount);
        lastDistribution = block.timestamp;
        nextDistribution = lastDistribution + timeInterval;
    }

    function emergencyWithdraw() public onlyOwner {
        IERC20 token = IERC20(nexusToken);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }
}