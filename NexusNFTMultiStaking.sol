// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./NexusSwap/Interfaces/INexusNFTWeight.sol";

contract NexusNFTMultiStaking is Ownable, ReentrancyGuard, ERC721Holder {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using SafeERC20 for IERC20;

    event OnTokenLock(
        address indexed owner,
        uint256 amount,
        uint256 unlockTime,
        uint8 lockMode
    );

    event OnTokenUnlock(address user);

    event OnLockWithdrawal(address user, uint256 amount, uint8 mode);

    event OnLockAmountIncreased(address user, uint256 amount);

    event OnLockDurationIncreased(address user, uint256 newUnlockTime);

    uint256 public PRECISION_FACTOR = 10**8;

    address public constant deadAddress =
        0x000000000000000000000000000000000000dEaD;

    address public immutable nexusToken;

    uint256[] public LOCK_TIME_MULTIPLIER = [10, 15, 70, 150, 310];

    uint256[] public LOCK_TIME_DURATION = [
        0,
        30 minutes,
        90 minutes,
        180 minutes,
        365 minutes
    ];

    address public immutable nexusNFT;

    uint256 public minNexusAmount = 1111 * 10**18;

    uint256 public minNexusCollateralAmount = 100 * 10**18;

    uint256 private constant PERCENT_FACTOR = 1e4;

    address public nexusWeight;

    struct TokenLock {
        uint256 totalWeight;
        uint256 unlockTime;
        uint256 nftWeight;
        uint256 lockedAmount; // How many staked tokens the user has provided,
        uint256 lockMode; // duration
        uint256 nexusLock;
    }

    struct Reward {
        address token;
        uint256 amount;
    }

    address public distributor;

    modifier onlyDistributorOrOwner() {
        require(
            msg.sender == distributor || msg.sender == owner(),
            "caller is not distributor or owner"
        );
        _;
    }

    mapping(address => TokenLock) public userLocks;

    mapping(address => EnumerableSet.UintSet) private userNFTBalances;

    uint256 public totalPoolWeight;

    uint256 public totalnexusLocked;

    uint256 public totalNFTWeight;

    bool public enableEmergency;

    uint256[] public nexusAmountForLock = new uint256[](5);

    EnumerableMap.AddressToUintMap private accRewardPerWeight;

    EnumerableMap.AddressToUintMap private totalReward;

    mapping(address => EnumerableMap.AddressToUintMap) private userDebtRewards;

    mapping(address => EnumerableMap.AddressToUintMap) private userTotalReward;

    EnumerableSet.UintSet private rewardHistoryTimes;

    mapping(uint256 => Reward) private rewardHistory;

    receive() external payable {}

    fallback() external payable {}

    constructor(
        address _nexusToken,
        address _nexusNFT,
        address _nexusWeight
    ) {
        require(_nexusWeight != address(0), "wrong weighter");
        require(_nexusToken != address(0), "wrong weighter");
        nexusToken = _nexusToken;
        nexusWeight = _nexusWeight;
        nexusNFT = _nexusNFT;
    }

    function totalStakedNFTCount() public view returns (uint256 tokenCount) {
        tokenCount = IERC721Enumerable(nexusNFT).balanceOf(address(this));
    }

    function totalStakedNFT() external view returns (uint256[] memory) {
        uint256 tokenCount = IERC721Enumerable(nexusNFT).balanceOf(
            address(this)
        );
        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = IERC721Enumerable(nexusNFT).tokenOfOwnerByIndex(
                    address(this),
                    index
                );
            }
            return result;
        }
    }

    function userWalletNFT(address _owner)
        external
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = IERC721Enumerable(nexusNFT).balanceOf(_owner);
        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = IERC721Enumerable(nexusNFT).tokenOfOwnerByIndex(
                    _owner,
                    index
                );
            }
            return result;
        }
    }

    function userStakedNFT(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        return userNFTBalances[_owner].values();
    }

    function userStakedNFTCount(address _owner) public view returns (uint256) {
        return userNFTBalances[_owner].length();
    }

    function isStaked(address account, uint256 tokenId)
        public
        view
        returns (bool)
    {
        return userNFTBalances[account].contains(tokenId);
    }

    function distributeReward(address token, uint256 _amount)
        public
        payable
        onlyDistributorOrOwner
    {
        require(_amount > 0, "zero reward");

        if (token != address(0)) {
            uint256 beforeBalance = IERC20(token).balanceOf(address(this));

            IERC20(token).safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );

            uint256 afterBalance = IERC20(token).balanceOf(address(this));

            _amount = afterBalance - beforeBalance;
        } else {
            _amount = msg.value;
        }

        if (totalPoolWeight > 0) {
            (, uint256 lastValue) = accRewardPerWeight.tryGet(token);

            uint256 newValue = lastValue +
                (_amount * PRECISION_FACTOR) /
                totalPoolWeight;
            accRewardPerWeight.set(token, newValue);
        }

        (, uint256 lastTotalValue) = totalReward.tryGet(token);
        uint256 newTotalValue = lastTotalValue + _amount;
        totalReward.set(token, newTotalValue);

        rewardHistoryTimes.add(block.timestamp);

        rewardHistory[block.timestamp] = Reward({
            token: token,
            amount: _amount
        });
    }

    function backToPool(address token, uint256 _amount) private {
        if (totalPoolWeight > 0) {
            (, uint256 lastValue) = accRewardPerWeight.tryGet(token);
            uint256 newValue = lastValue +
                (_amount * PRECISION_FACTOR) /
                totalPoolWeight;
            accRewardPerWeight.set(token, newValue);
        }

        (, uint256 lastTotalValue) = totalReward.tryGet(token);
        uint256 newTotalValue = lastTotalValue + _amount;
        totalReward.set(token, newTotalValue);

        rewardHistoryTimes.add(block.timestamp);

        rewardHistory[block.timestamp] = Reward({
            token: token,
            amount: _amount
        });
    }

    function distributedUserTotalReward(address user)
        external
        view
        returns (Reward[] memory rewards)
    {
        uint256 rewardCount = userTotalReward[user].length();

        rewards = new Reward[](rewardCount);

        for (uint256 i; i < rewardCount; ) {
            (address token, uint256 distributed) = userTotalReward[user].at(i);
            rewards[i] = Reward({token: token, amount: distributed});

            unchecked {
                i++;
            }
        }
    }

    function distributedTotalReward()
        external
        view
        returns (Reward[] memory rewards)
    {
        uint256 rewardCount = totalReward.length();

        rewards = new Reward[](rewardCount);

        for (uint256 i; i < rewardCount; ) {
            (address token, uint256 distributed) = totalReward.at(i);
            rewards[i] = Reward({token: token, amount: distributed});

            unchecked {
                i++;
            }
        }
    }

    function updateDebt() private {
        TokenLock storage lock = userLocks[msg.sender];

        if (lock.totalWeight > 0) {
            uint256 rewardCount = accRewardPerWeight.length();

            for (uint256 i; i < rewardCount; ) {
                (address token, uint256 acc) = accRewardPerWeight.at(i);

                uint256 newDebt = (lock.totalWeight * acc) / PRECISION_FACTOR;

                userDebtRewards[msg.sender].set(token, newDebt);

                unchecked {
                    i++;
                }
            }
        }
    }

    function pendingRewards(address user)
        external
        view
        returns (Reward[] memory rewards)
    {
        TokenLock memory lock = userLocks[user];

        if (lock.totalWeight > 0) {
            uint256 rewardCount = accRewardPerWeight.length();

            rewards = new Reward[](rewardCount);

            for (uint256 i; i < rewardCount; ) {
                (address token, uint256 acc) = accRewardPerWeight.at(i);

                (, uint256 debtReward) = userDebtRewards[user].tryGet(token);

                uint256 reward = (lock.totalWeight * acc) /
                    PRECISION_FACTOR -
                    debtReward;

                rewards[i] = Reward({token: token, amount: reward});

                unchecked {
                    i++;
                }
            }
        }
    }

    function _harvest() internal {
        TokenLock storage lock = userLocks[msg.sender];

        if (lock.totalWeight > 0) {
            uint256 rewardCount = accRewardPerWeight.length();

            for (uint256 i; i < rewardCount; ) {
                (address token, uint256 acc) = accRewardPerWeight.at(i);
                (, uint256 debtReward) = userDebtRewards[msg.sender].tryGet(
                    token
                );

                uint256 reward = (lock.totalWeight * acc) /
                    PRECISION_FACTOR -
                    debtReward;

                if (reward > 0) {
                    if (token == address(0)) {
                        transferETH(msg.sender, reward);
                    } else {
                        IERC20(token).safeTransfer(msg.sender, reward);
                    }

                    (, uint256 lastTotalValue) = userTotalReward[msg.sender]
                        .tryGet(token);
                    uint256 newTotalValue = lastTotalValue + reward;
                    userTotalReward[msg.sender].set(token, newTotalValue);
                }

                uint256 newDebt = (lock.totalWeight * acc) / PRECISION_FACTOR;

                userDebtRewards[msg.sender].set(token, newDebt);

                unchecked {
                    i++;
                }
            }
        }
    }

    function harvest() public {
        _harvest();

        TokenLock storage lock = userLocks[msg.sender];
        if (lock.unlockTime < block.timestamp && lock.lockMode > 0) {
            shortenLockTime(0);
        }
    }

    function rewardBackToPool() private {
        TokenLock storage lock = userLocks[msg.sender];

        if (lock.totalWeight > 0) {
            uint256 rewardCount = accRewardPerWeight.length();

            for (uint256 i; i < rewardCount; ) {
                (address token, uint256 acc) = accRewardPerWeight.at(i);
                (, uint256 debtReward) = userDebtRewards[msg.sender].tryGet(
                    token
                );

                uint256 reward = (lock.totalWeight * acc) /
                    PRECISION_FACTOR -
                    debtReward;

                if (reward > 0) {
                    if (totalPoolWeight > 0) {
                        (, uint256 lastValue) = accRewardPerWeight.tryGet(
                            token
                        );

                        uint256 newValue = lastValue +
                            (reward * PRECISION_FACTOR) /
                            totalPoolWeight;
                        accRewardPerWeight.set(token, newValue);
                    }

                    (, uint256 lastTotalValue) = totalReward.tryGet(token);
                    uint256 newTotalValue = lastTotalValue + reward;
                    totalReward.set(token, newTotalValue);

                    rewardHistoryTimes.add(block.timestamp + i);

                    rewardHistory[block.timestamp + i] = Reward({
                        token: token,
                        amount: reward
                    });
                }

                uint256 newDebt = (lock.totalWeight * acc) / PRECISION_FACTOR;

                userDebtRewards[msg.sender].set(token, newDebt);

                unchecked {
                    i++;
                }
            }
        }
    }

    function depositNexusBar(uint256 amount) private {
        require(amount > 0, "zero amount");

        require(
            IERC20(nexusToken).balanceOf(msg.sender) >= amount,
            "small nexusToken balance to stake"
        );

        require(
            IERC20(nexusToken).allowance(msg.sender, address(this)) >= amount,
            "small nexusToken allowance to stake"
        );

        uint256 beforeBalance = IERC20(nexusToken).balanceOf(address(this));

        IERC20(nexusToken).safeTransferFrom(
            address(msg.sender),
            address(this),
            amount
        );

        uint256 afterBalance = IERC20(nexusToken).balanceOf(address(this));

        amount = afterBalance - beforeBalance;

        TokenLock storage lock = userLocks[msg.sender];

        lock.nexusLock += amount;

        totalnexusLocked += amount;
    }

    function withdrawNexusBar(uint256 amount) private {
        require(amount > 0, "zero amount");

        TokenLock storage lock = userLocks[msg.sender];

        // require(lock.nexusLock >= amount, "small lock amount");

        uint8 mode = 0;

        if (block.timestamp < lock.unlockTime) {
            mode = 1;
        }

        uint256 tokenFee = (amount * 50 * mode) / 100;

        uint256 amountWithdraw = amount - tokenFee;

        IERC20(nexusToken).safeTransfer(msg.sender, amountWithdraw);

        if (mode == 1) {
            uint256 burnAmount = (tokenFee * 50) / 100;

            IERC20(nexusToken).safeTransfer(deadAddress, burnAmount);

            backToPool(nexusToken, tokenFee - burnAmount);
        }

        lock.nexusLock -= amount;

        totalnexusLocked -= amount;
    }

    function batchNFTStake(uint256[] calldata tokenIds) public nonReentrant {
        require(
            IERC721(nexusNFT).isApprovedForAll(_msgSender(), address(this)),
            "Not approve nft to staker address"
        );

        uint256 count = tokenIds.length;

        require(count > 0, "zero stake nft");

        TokenLock storage lock = userLocks[msg.sender];

        if (lock.lockMode != 0) {
            if (lock.lockedAmount > 0) {
                require(
                    lock.lockedAmount >= minNexusAmount,
                    "small nexus staked"
                );
                depositNexusBar(minNexusCollateralAmount * count);
            }
        }

        uint256 newWeight = lock.nftWeight;

        uint256 addedWeight = 0;

        for (uint256 i = 0; i < count; ) {
            uint256 tokenId = tokenIds[i];

            require(
                IERC721(nexusNFT).ownerOf(tokenId) == _msgSender(),
                "wrong owner"
            );

            IERC721(nexusNFT).safeTransferFrom(
                _msgSender(),
                address(this),
                tokenId
            );

            userNFTBalances[_msgSender()].add(tokenId);

            uint256 nexusNFTWeight = INexusNFTWeight(nexusWeight)
                .nexusNFTWeight(tokenId) * 10**18;
            newWeight += nexusNFTWeight;

            // addedWeight +=
            //     (nexusNFTWeight * LOCK_TIME_MULTIPLIER[lock.lockMode]) /
            //     10;

            if (lock.lockedAmount > 0) {
                addedWeight +=
                    (nexusNFTWeight * LOCK_TIME_MULTIPLIER[lock.lockMode]) /
                    10;
            } else {
                addedWeight += nexusNFTWeight;
            }

            unchecked {
                i++;
            }
        }

        _harvest();

        lock.nftWeight = newWeight;

        lock.totalWeight = addedWeight + lock.totalWeight;

        totalPoolWeight += addedWeight;
        
        if (lock.unlockTime < block.timestamp && lock.lockMode > 0) {
            shortenLockTime(0);
        } else {
            updateDebt();
        }
    }

    function NFTStake(uint256 tokenId) public nonReentrant {
        require(
            IERC721(nexusNFT).ownerOf(tokenId) == _msgSender(),
            "wrong owner"
        );

        require(
            IERC721(nexusNFT).isApprovedForAll(_msgSender(), address(this)) ||
                IERC721(nexusNFT).getApproved(tokenId) == address(this),
            "not approved"
        );

        TokenLock storage lock = userLocks[msg.sender];

        if (lock.lockMode != 0) {
            if (lock.lockedAmount > 0) {
                require(
                    lock.lockedAmount >= minNexusAmount,
                    "small nexus staked"
                );
                depositNexusBar(minNexusCollateralAmount);
            }
        }

        IERC721(nexusNFT).safeTransferFrom(
            _msgSender(),
            address(this),
            tokenId
        );

        _harvest();

        userNFTBalances[_msgSender()].add(tokenId);

        uint256 oldWeight = lock.nftWeight;
        uint256 nexusNFTWeight = INexusNFTWeight(nexusWeight).nexusNFTWeight(
            tokenId
        ) * 10**18;
        uint256 newWeight = oldWeight + nexusNFTWeight;

        lock.nftWeight = newWeight;
        uint256 addedWeight;
        if (lock.lockedAmount > 0) {
            addedWeight =
                (nexusNFTWeight * LOCK_TIME_MULTIPLIER[lock.lockMode]) /
                10;
        } else {
            addedWeight = nexusNFTWeight;
        }
        lock.totalWeight += addedWeight;
        totalPoolWeight += addedWeight;

        if (lock.unlockTime < block.timestamp && lock.lockMode > 0) {
            shortenLockTime(0);
        } else {
            updateDebt();
        }
    }

    function NFTWithdraw(uint256 tokenId) public nonReentrant {
        require(isStaked(_msgSender(), tokenId), "Not staked this nft");

        IERC721(nexusNFT).safeTransferFrom(
            address(this),
            _msgSender(),
            tokenId
        );

        TokenLock storage lock = userLocks[msg.sender];

        if (lock.nexusLock >= minNexusCollateralAmount) {
            withdrawNexusBar(minNexusCollateralAmount);
        } else if (lock.nexusLock > 0) {
            withdrawNexusBar(lock.nexusLock);
        }

        userNFTBalances[_msgSender()].remove(tokenId);

        _harvest();

        uint256 oldWeight = lock.nftWeight;

        uint256 nexusNFTWeight = INexusNFTWeight(nexusWeight).nexusNFTWeight(
            tokenId
        ) * 10**18;

        uint256 newWeight = oldWeight - nexusNFTWeight;

        lock.nftWeight = newWeight;

        uint256 reduceddWeight;

        //  (nexusNFTWeight *
        //     LOCK_TIME_MULTIPLIER[lock.lockMode]) / 10;

        if (lock.lockedAmount > 0) {
            reduceddWeight =
                (nexusNFTWeight * LOCK_TIME_MULTIPLIER[lock.lockMode]) /
                10;
        } else {
            reduceddWeight = nexusNFTWeight;
        }

        lock.totalWeight -= reduceddWeight;
        totalPoolWeight -= reduceddWeight;

        if (lock.unlockTime < block.timestamp && lock.lockMode > 0) {
            shortenLockTime(0);
        } else {
            updateDebt();
        }

        if (lock.lockedAmount == 0) {
            if (userStakedNFTCount(msg.sender) == 0) {
                delete userLocks[msg.sender];
            }
            emit OnTokenUnlock(msg.sender);
        }
    }

    function batchNFTWithdraw(uint256[] calldata tokenIds) public nonReentrant {
        uint256 count = tokenIds.length;

        require(count > 0, "zero stake nft");

        TokenLock storage lock = userLocks[msg.sender];

        uint256 newWeight = lock.nftWeight;

        uint256 reduceddWeight = 0;

        for (uint256 i = 0; i < count; ) {
            uint256 tokenId = tokenIds[i];

            require(isStaked(_msgSender(), tokenId), "Not staked this nft");

            IERC721(nexusNFT).safeTransferFrom(
                address(this),
                _msgSender(),
                tokenId
            );

            userNFTBalances[_msgSender()].remove(tokenId);

            uint256 nexusNFTWeight = INexusNFTWeight(nexusWeight)
                .nexusNFTWeight(tokenId) * 10**18;

            newWeight -= nexusNFTWeight;

            // reduceddWeight +=
            //     (nexusNFTWeight * LOCK_TIME_MULTIPLIER[lock.lockMode]) /
            //     10;

            if (lock.lockedAmount > 0) {
                reduceddWeight +=
                    (nexusNFTWeight * LOCK_TIME_MULTIPLIER[lock.lockMode]) /
                    10;
            } else {
                reduceddWeight += nexusNFTWeight;
            }

            unchecked {
                i++;
            }
        }

        _harvest();

        if (lock.nexusLock >= minNexusCollateralAmount * count) {
            withdrawNexusBar(minNexusCollateralAmount * count);
        } else if (lock.nexusLock > 0) {
            withdrawNexusBar(lock.nexusLock);
        }

        lock.nftWeight = newWeight;

        lock.totalWeight -= reduceddWeight;
        totalPoolWeight -= reduceddWeight;

        if (lock.unlockTime < block.timestamp && lock.lockMode > 0) {
            shortenLockTime(0);
        } else {
            updateDebt();
        }

        if (lock.lockedAmount == 0) {
            if (userStakedNFTCount(msg.sender) == 0) {
                delete userLocks[msg.sender];
            }
            emit OnTokenUnlock(msg.sender);
        }
    }

    function calculateUserNFTWeight(address _account)
        public
        view
        returns (uint256 weight)
    {
        uint256 tokenCount = userNFTBalances[_account].length();
        if (tokenCount == 0) {
            return 0;
        } else {
            uint256[] memory staked = userStakedNFT(_account);
            uint256 i;
            for (i; i < tokenCount; ) {
                weight +=
                    INexusNFTWeight(nexusWeight).nexusNFTWeight(staked[i]) *
                    10**18;
                unchecked {
                    i++;
                }
            }
        }
    }

    /**
     * @notice locks nexus token until specified time
     * @param amount amount of tokens to lock
     * @param lockMode unix time in seconds after that tokens can be withdrawn
     */
    function deposit(uint256 amount, uint8 lockMode)
        external
        payable
        nonReentrant
    {
        require(amount > 0, "ZERO AMOUNT");

        require(
            IERC20(nexusToken).balanceOf(msg.sender) >= amount,
            "small NEXUS balance to stake"
        );

        require(
            IERC20(nexusToken).allowance(msg.sender, address(this)) >= amount,
            "small NEXUS allowance to stake"
        );

        require(lockMode >= 0 && lockMode < 5, "Invalid lock mode");

        TokenLock storage lock = userLocks[msg.sender];

        require(lock.lockedAmount == 0, "already deposit");

        uint256 beforeBalance = IERC20(nexusToken).balanceOf(address(this));

        IERC20(nexusToken).safeTransferFrom(
            address(msg.sender),
            address(this),
            amount
        );

        uint256 afterBalance = IERC20(nexusToken).balanceOf(address(this));

        amount = afterBalance - beforeBalance;

        uint256 unlockTime = block.timestamp + LOCK_TIME_DURATION[lockMode];

        uint256 addeddWeight = (amount * LOCK_TIME_MULTIPLIER[lockMode]) / 10;

        if (lock.nftWeight > 0) {
            addeddWeight +=
                (lock.nftWeight * (LOCK_TIME_MULTIPLIER[lockMode] - 10)) /
                10;

            if (lockMode > 0) {
                require(amount >= minNexusAmount, "small nexus amount for nft");

                uint256 count = userStakedNFTCount(msg.sender);

                if (
                    count > 0 &&
                    minNexusCollateralAmount * count > lock.nexusLock
                ) {
                    depositNexusBar(
                        minNexusCollateralAmount * count - lock.nexusLock
                    );
                }
            }
        }

        _harvest();

        totalPoolWeight += addeddWeight;

        nexusAmountForLock[lockMode] += amount;

        lock.totalWeight += addeddWeight;
        lock.lockedAmount += amount;

        if (lock.unlockTime < unlockTime) {
            lock.unlockTime = unlockTime;
        }

        lock.lockMode = lockMode;
        updateDebt();

        emit OnTokenLock(msg.sender, amount, unlockTime, lockMode);
    }

    function extendLockTime(uint256 lockMode) external nonReentrant {
        require(lockMode > 0 && lockMode < 5, "Invalid lock mode");

        TokenLock storage lock = userLocks[msg.sender];
        require(lock.lockedAmount > 0, "no lock");
        require(lock.lockMode < lockMode, "NOT INCREASING UNLOCK TIME");

        uint256 count = userStakedNFTCount(msg.sender);
        uint256 unlockTime = lock.unlockTime +
            LOCK_TIME_DURATION[lockMode] -
            LOCK_TIME_DURATION[lock.lockMode];
        uint256 addedWeight = ((lock.lockedAmount + lock.nftWeight) *
            (LOCK_TIME_MULTIPLIER[lockMode] -
                LOCK_TIME_MULTIPLIER[lock.lockMode])) / 10;

        uint256 requiredCollateral = count * minNexusCollateralAmount;
        uint256 additionalCollateralNeeded = 0;

        if (lock.nexusLock < requiredCollateral) {
            additionalCollateralNeeded = requiredCollateral - lock.nexusLock;
            // Check user balance and allowance before proceeding
            require(
                IERC20(nexusToken).balanceOf(msg.sender) >=
                    additionalCollateralNeeded,
                "Insufficient balance for additional collateral"
            );
            require(
                IERC20(nexusToken).allowance(msg.sender, address(this)) >=
                    additionalCollateralNeeded,
                "Insufficient allowance for additional collateral"
            );

            depositNexusBar(additionalCollateralNeeded);
        }

        _harvest();

        totalPoolWeight += addedWeight;
        nexusAmountForLock[lock.lockMode] -= lock.lockedAmount;
        nexusAmountForLock[lockMode] += lock.lockedAmount;

        lock.totalWeight += addedWeight;
        lock.lockMode = lockMode;
        lock.unlockTime = unlockTime;

        updateDebt();

        emit OnLockDurationIncreased(msg.sender, unlockTime);
    }

    function shortenLockTime(uint256 lockMode) internal {
        require(lockMode >= 0 && lockMode < 5, "Invalid lock mode");

        TokenLock storage lock = userLocks[msg.sender];

        require(lock.lockMode > lockMode, "NOT DECREASING UNLOCK TIME");

        require(lock.unlockTime < block.timestamp, "original lock duration");

        uint256 unlockTime = block.timestamp + LOCK_TIME_DURATION[lockMode];

        uint256 reducedWeight = ((lock.lockedAmount + lock.nftWeight) *
            (LOCK_TIME_MULTIPLIER[lock.lockMode] -
                LOCK_TIME_MULTIPLIER[lockMode])) / 10;

        totalPoolWeight -= reducedWeight;

        nexusAmountForLock[lock.lockMode] -= lock.lockedAmount;

        nexusAmountForLock[lockMode] += lock.lockedAmount;

        lock.totalWeight -= reducedWeight;

        lock.lockMode = lockMode;

        lock.unlockTime = unlockTime;

        updateDebt();
    }

    /**
     * @notice add tokens to an existing lock
     * @param amount tokens amount to add
     */
    function increaseLockAmount(uint256 amount) external payable nonReentrant {
        require(amount > 0, "ZERO AMOUNT");

        TokenLock storage lock = userLocks[msg.sender];

        require(lock.lockedAmount > 0, "no original lock");

        uint256 beforeBalance = IERC20(nexusToken).balanceOf(address(this));

        IERC20(nexusToken).safeTransferFrom(
            address(msg.sender),
            address(this),
            amount
        );

        uint256 afterBalance = IERC20(nexusToken).balanceOf(address(this));

        amount = afterBalance - beforeBalance;

        _harvest();

        uint256 addeddWeight = ((amount) *
            LOCK_TIME_MULTIPLIER[lock.lockMode]) / 10;

        totalPoolWeight += addeddWeight;

        nexusAmountForLock[lock.lockMode] += amount;

        lock.totalWeight += addeddWeight;
        lock.lockedAmount += amount;

        if (lock.unlockTime < block.timestamp && lock.lockMode > 0) {
            shortenLockTime(0);
        } else {
            updateDebt();
        }

        emit OnLockAmountIncreased(msg.sender, amount);
    }

    /**
     * @notice withdraw specified amount of tokens from lock. Current time must be greater than unlock time
     * @param amount amount of tokens to withdraw
     */
    function withdraw(uint256 amount) public nonReentrant {
        TokenLock storage lock = userLocks[msg.sender];

        require(lock.lockedAmount >= amount, "more withdraw");

        require(amount > 0, "zero amount");

        uint8 mode = 0;

        if (block.timestamp < lock.unlockTime) {
            mode = 1;
            rewardBackToPool();
        } else {
            _harvest();
        }

        uint256 tokenFee = (amount * 50 * mode) / 100;

        uint256 amountWithdraw = amount - tokenFee;

        if (amountWithdraw > 0) {
            IERC20(nexusToken).safeTransfer(msg.sender, amountWithdraw);
        }

        if (mode == 1) {
            uint256 burnAmount = (tokenFee * 5) / 10;
            IERC20(nexusToken).safeTransfer(deadAddress, burnAmount);
            backToPool(nexusToken, tokenFee - burnAmount);
        }

        nexusAmountForLock[lock.lockMode] -= amount;

        lock.lockedAmount -= amount;

        if (lock.lockedAmount == 0) {
            totalPoolWeight =
                totalPoolWeight +
                lock.nftWeight -
                lock.totalWeight;

            if (userStakedNFTCount(msg.sender) == 0) {
                delete userLocks[msg.sender];
            } else {
                // lock.lockMode = 0;
                lock.totalWeight = lock.nftWeight;
            }
        } else {
            uint256 reducedWeight = (amount *
                LOCK_TIME_MULTIPLIER[lock.lockMode]) / 10;

            totalPoolWeight -= reducedWeight;

            lock.totalWeight -= reducedWeight;
        }

        if (lock.unlockTime < block.timestamp && lock.lockMode > 0) {
            shortenLockTime(0);
        } else {
            updateDebt();
        }

        if (lock.lockedAmount == 0) {
            emit OnTokenUnlock(msg.sender);
        } else {
            emit OnLockWithdrawal(msg.sender, amount, mode);
        }
    }

    function transferETH(address recipient, uint256 amount) private {
        (bool res, ) = payable(recipient).call{value: amount}("");
        require(res, "ETH TRANSFER FAILED");
    }

    function totalNexusLocked() public view returns (uint256 amount) {
        for (uint256 i; i < nexusAmountForLock.length; ) {
            amount += nexusAmountForLock[i];
            unchecked {
                i++;
            }
        }
    }

    function setNexusWeight(address _nexusWeight) external onlyOwner {
        require(_nexusWeight != address(0), "wrong address");
        nexusWeight = _nexusWeight;
    }

    function setMinNexusCollateral(uint256 _min) external onlyOwner {
        minNexusCollateralAmount = _min;
    }

    function setMinNexusAmount(uint256 _min) external onlyOwner {
        minNexusAmount = _min;
    }

    function setEmergency(bool _flag) external onlyOwner {
        enableEmergency = _flag;
    }

    function setDistributor(address _distributor) external onlyOwner {
        distributor = _distributor;
    }

    function emergencyWithdraw() public nonReentrant {
        require(enableEmergency, "not emergency feature");

        // TokenLock storage lock = userLocks[msg.sender];

        uint256[] memory staked = userStakedNFT(msg.sender);

        uint256 count = staked.length;

        for (uint256 i = 0; i < count; ) {
            uint256 tokenId = staked[i];

            IERC721(nexusNFT).safeTransferFrom(
                address(this),
                _msgSender(),
                tokenId
            );

            userNFTBalances[_msgSender()].remove(tokenId);

            unchecked {
                i++;
            }
        }
    }

    function getGlobalStatus()
        external
        view
        returns (
            uint256 poolSize,
            uint256 nexusAmount,
            uint256 nftCount,
            uint256 NexusCollateralAmount
        )
    {
        poolSize = totalPoolWeight;
        nexusAmount = totalNexusLocked();
        nftCount = totalStakedNFTCount();
        NexusCollateralAmount = totalnexusLocked;
    }

    function getRewardHistory()
        external
        view
        returns (uint256[] memory times, Reward[] memory rewards)
    {
        uint256 rewardCount = rewardHistoryTimes.length();
        times = new uint256[](rewardCount);
        rewards = new Reward[](rewardCount);

        for (uint256 i; i < rewardCount; ) {
            uint256 rewardTime = rewardHistoryTimes.at(i);
            rewards[i] = rewardHistory[rewardTime];
            times[i] = rewardTime;

            unchecked {
                i++;
            }
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
