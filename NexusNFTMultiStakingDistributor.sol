// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./NexusSwap/Interfaces/INexusStaking.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract NexusNFTMultiStakingDistributor is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    EnumerableSet.AddressSet private rewardTokens;

    address public nexusStaker;

    uint256 public minAmount;

    constructor(address _staker) {
        require(_staker != address(0),"wrong staker");
        nexusStaker = _staker;
    }

    receive() external payable {}

    fallback() external payable {}

    function setMinAmount(uint256 _amount) external onlyOwner {
        require(_amount > 0, "wrong amount");
        minAmount = _amount;
    }

    function setStaker(address _staker) external onlyOwner {
        require(_staker != address(0), "wrong address");
        nexusStaker = _staker;
    }

    function addRewardToken(address token) external onlyOwner {
        require(token != address(0), "wrong token");
        rewardTokens.add(token);
    }

    function removeRewardToken(address token) external onlyOwner {
        require(token != address(0), "wrong token");
        rewardTokens.remove(token);
    }

    function distribute() external  {
        uint256 rewardCount = rewardTokens.length();

        uint256 currentBalance;
        for (uint256 i; i < rewardCount; ) {
            address token = rewardTokens.at(i);

            currentBalance = IERC20(token).balanceOf(address(this));
            if (currentBalance > minAmount) {
                SafeERC20.safeApprove(IERC20(token), nexusStaker, currentBalance);  
                INexusStaking(nexusStaker).distributeReward(token, currentBalance);
            }

            unchecked {
                i++;
            }
        }

        currentBalance = address(this).balance;
        if(currentBalance > minAmount){
            INexusStaking(nexusStaker).distributeReward{value:currentBalance}(address(0), currentBalance);
        }
    }

    function possibleDistribute() external view returns(bool)  {
        uint256 rewardCount = rewardTokens.length();

        uint256 currentBalance;
        for (uint256 i; i < rewardCount; ) {
            address token = rewardTokens.at(i);

            currentBalance = IERC20(token).balanceOf(address(this));
            if (currentBalance > minAmount) {
                return true;
            }

            unchecked {
                i++;
            }
        }

        currentBalance = address(this).balance;
        if(currentBalance > minAmount){
            return true;
        }
        return false;
    }
}
