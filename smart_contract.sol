// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// ========== Imports from OpenZeppelin ==========
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/security/ReentrancyGuard.sol";


contract SpaceDogeX is ERC20, Ownable, ReentrancyGuard {
    // ========== Events ==========
    event TaxFeeUpdated(uint256 newTaxFee);
    event BurnFeeUpdated(uint256 newBurnFee);
    event StakingRewardUpdated(uint256 newStakingReward);
    event MarketingWalletUpdated(address newMarketingWallet);
    event TransactionCooldownUpdated(uint256 newCooldown);
    event TokensStaked(address indexed user, uint256 amount);
    event StakingRewardClaimed(address indexed user, uint256 reward);
    event AirdropClaimed(address indexed user, uint256 amount);
    event MinBalanceRequiredUpdated(uint256 newMinBalance);
    event AirdropPercentageUpdated(uint256 newPercentage);
    event RewardDistributed(uint256 rewardPool);
    event LiquidityStatusChanged(bool enabled);
    event VoteCast(address indexed voter, uint256 proposalId, uint256 weight);

    // Additional event for Pools
    event PoolCreated(uint256 indexed poolId, uint256 rewardRate, uint256 lockPeriod);

    // ========== State Variables ==========
    uint256 public taxFee = 4;
    uint256 public burnFee = 1;
    uint256 public stakingReward = 2;
    address public marketingWallet;

    // Cooldown
    mapping(address => uint256) public lastTransactionNonce;
    mapping(address => uint256) public lastTransactionTimestamp;
    uint256 public transactionCooldown = 60 seconds;

    // Airdrop
    uint256 public minBalanceRequired;
    uint256 public airdropPercentage;
    mapping(address => bool) public eligibleForAirdrop;
    mapping(address => bool) public hasClaimedAirdrop;

    // Basic Staking (old)
    mapping(address => uint256) public stakingStartTime;
    mapping(address => uint256) public stakedBalance;
    uint256 public maxStakingPeriod = 365 days; // not strictly used

    // Batch Rewards
    mapping(address => bool) public isRewardEligible;
    address[] private rewardEligibleAddresses;
    uint256 public lastRewardDistribution;
    uint256 public rewardInterval = 7 days;
    uint256 public minRewardAmount = 1 ether;
    uint256 public batchSize = 50;

    // DAO Voting
    struct Proposal {
        string description;
        uint256 voteCount;
        uint256 startTime;
        uint256 duration;
        bool executed;
    }
    Proposal[] public proposals;

    struct VoteInfo {
        uint256 weight;
        bool voted;
    }
    mapping(address => mapping(uint256 => VoteInfo)) public hasVoted;
    uint256 public maxVotePower = 500000 * 10**decimals();

    // Enhanced Ownership
    mapping(address => bool) private trustedOwners;
    uint256 public ownershipTimelock = 2 days;
    uint256 private lastOwnershipTransferTime;

    // Liquidity Lock
    bool public liquidityEnabled;
    uint256 public liquidityUnlockTime;
    uint256 public minLockPeriod = 30 days;

    // Multiple Pools
    struct StakePool {
        uint256 id;
        uint256 rewardRate; // e.g. 5 means 5%
        uint256 lockPeriod; // e.g. 30 days
        bool active;
    }
    StakePool[] public stakePools;

    mapping(address => mapping(uint256 => uint256)) public stakedBalanceInPool;
    mapping(address => mapping(uint256 => uint256)) public stakingStartTimeInPool;

    // ========== Constructor ==========
    // If your Ownable version doesn't require an address param, use just `Ownable()`.
    constructor() ERC20("SpaceDogeX", "SPADX") {
        _mint(msg.sender, 420_000_000_000 * 10**decimals());

    // Example marketing wallet
         marketingWallet = 0x813610fdbF080a9Fb765496b09139c67F91Ed565;

         minBalanceRequired = 1000 * 10**decimals();
         airdropPercentage = 1; // 1% of total supply
    }

    // =====================================================
    //  _transfer (override) with cooldown, tax, and burn
    // =====================================================
    // Requires a modern OpenZeppelin version where _transfer is virtual.
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        // Cooldown check
        require(
            block.timestamp >= lastTransactionTimestamp[sender] + transactionCooldown,
            "Cooldown period active"
        );
        lastTransactionTimestamp[sender] = block.timestamp;
        lastTransactionNonce[sender]++;

        // Calculate tax & burn
        uint256 taxAmount = (amount * taxFee) / 100;
        uint256 burnAmount = (amount * burnFee) / 100;
        uint256 finalAmount = amount - taxAmount - burnAmount;

        // transfer final to recipient
        super._transfer(sender, recipient, finalAmount);

        // transfer tax to marketing wallet
        if (taxAmount > 0) {
            super._transfer(sender, marketingWallet, taxAmount);
        }

        // burn if needed
        if (burnAmount > 0) {
            _burn(sender, burnAmount);
        }
    }

    // ========== Setters & Admin Functions ==========
    function setTransactionCooldown(uint256 _cooldown) external onlyOwner {
        transactionCooldown = _cooldown;
        emit TransactionCooldownUpdated(_cooldown);
    }

    function setTaxFee(uint256 _taxFee) external onlyOwner {
        require(_taxFee <= 5, "Tax too high");
        taxFee = _taxFee;
        emit TaxFeeUpdated(_taxFee);
    }

    function setBurnFee(uint256 _burnFee) external onlyOwner {
        require(_burnFee <= 5, "Burn fee too high");
        burnFee = _burnFee;
        emit BurnFeeUpdated(_burnFee);
    }

    function setStakingReward(uint256 _stakingReward) external onlyOwner {
        require(_stakingReward <= 10, "Staking reward too high");
        stakingReward = _stakingReward;
        emit StakingRewardUpdated(_stakingReward);
    }

    function setMarketingWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "Invalid address");
        marketingWallet = _wallet;
        emit MarketingWalletUpdated(_wallet);
    }

    // ========== Airdrop ==========
    function setMinBalanceRequired(uint256 _minBalance) external onlyOwner {
        minBalanceRequired = _minBalance;
        emit MinBalanceRequiredUpdated(_minBalance);
    }

    function setAirdropPercentage(uint256 _percentage) external onlyOwner {
        require(_percentage > 0, "Invalid percentage");
        airdropPercentage = _percentage;
        emit AirdropPercentageUpdated(_percentage);
    }

    function addAirdropEligibility(address account) external onlyOwner {
        require(balanceOf(account) >= minBalanceRequired, "Balance < required");
        eligibleForAirdrop[account] = true;
    }

    function removeAirdropEligibility(address account) external onlyOwner {
        eligibleForAirdrop[account] = false;
    }

    function claimAirdrop() external nonReentrant {
        require(eligibleForAirdrop[msg.sender], "Not eligible for airdrop");
        require(!hasClaimedAirdrop[msg.sender], "Airdrop already claimed");

        uint256 claimableAmount = (totalSupply() * airdropPercentage) / 100;
        require(balanceOf(address(this)) >= claimableAmount, "Not enough tokens in contract");

        hasClaimedAirdrop[msg.sender] = true;
        _transfer(address(this), msg.sender, claimableAmount);

        emit AirdropClaimed(msg.sender, claimableAmount);
    }

    // ========== Basic Staking (old) ==========
    function stakeTokens(uint256 amount) external {
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");
        _transfer(msg.sender, address(this), amount);

        stakedBalance[msg.sender] += amount;
        stakingStartTime[msg.sender] = block.timestamp;

        emit TokensStaked(msg.sender, amount);
    }

    function claimStakingRewards() external {
        require(stakedBalance[msg.sender] > 0, "No staked tokens");
        uint256 timeStaked = block.timestamp - stakingStartTime[msg.sender];
        require(timeStaked >= 30 days, "Must stake >= 30 days");

        uint256 multiplier = timeStaked / 30 days;
        require(multiplier >= 1, "Multiplier is zero");

        uint256 reward = (stakedBalance[msg.sender] * stakingReward * multiplier) / 100;
        _mint(msg.sender, reward);

        stakingStartTime[msg.sender] = block.timestamp;
        emit StakingRewardClaimed(msg.sender, reward);
    }

    // ========== Multiple Pools ==========
    function createPool(uint256 _rewardRate, uint256 _lockPeriod) external onlyOwner {
        require(_rewardRate <= 10, "Reward rate too high");

        stakePools.push(StakePool({
            id: stakePools.length,
            rewardRate: _rewardRate,
            lockPeriod: _lockPeriod,
            active: true
        }));

        emit PoolCreated(stakePools.length - 1, _rewardRate, _lockPeriod);
    }

    function setPoolStatus(uint256 poolId, bool _status) external onlyOwner {
        require(poolId < stakePools.length, "Invalid pool ID");
        stakePools[poolId].active = _status;
    }

    function stakeTokensInPool(uint256 poolId, uint256 amount) external {
        require(poolId < stakePools.length, "Invalid pool ID");
        StakePool storage pool = stakePools[poolId];
        require(pool.active, "Pool not active");
        require(balanceOf(msg.sender) >= amount, "Insufficient balance");

        _transfer(msg.sender, address(this), amount);

        stakedBalanceInPool[msg.sender][poolId] += amount;
        stakingStartTimeInPool[msg.sender][poolId] = block.timestamp;

        emit TokensStaked(msg.sender, amount);
    }

    function claimStakingRewardsFromPool(uint256 poolId) external {
        require(poolId < stakePools.length, "Invalid pool ID");
        StakePool storage pool = stakePools[poolId];
        require(pool.active, "Pool not active");

        uint256 staked = stakedBalanceInPool[msg.sender][poolId];
        require(staked > 0, "No staked tokens in this pool");

        uint256 timeStaked = block.timestamp - stakingStartTimeInPool[msg.sender][poolId];
        require(timeStaked >= pool.lockPeriod, "Lock period not passed");

        uint256 multiplier = timeStaked / pool.lockPeriod;
        require(multiplier >= 1, "Multiplier is zero");

        uint256 reward = (staked * pool.rewardRate * multiplier) / 100;
        _mint(msg.sender, reward);

        stakingStartTimeInPool[msg.sender][poolId] = block.timestamp;
        emit StakingRewardClaimed(msg.sender, reward);
    }

    // ========== Batch Reward Distribution ==========
    function addRewardEligible(address account) external onlyOwner {
        require(balanceOf(account) > 0, "Account must hold tokens");
        isRewardEligible[account] = true;
        rewardEligibleAddresses.push(account);
    }

    function removeRewardEligible(address account) external onlyOwner {
        isRewardEligible[account] = false;
    }

    function distributeRewards() external onlyOwner {
        require(
            block.timestamp >= lastRewardDistribution + rewardInterval,
            "Rewards interval not reached"
        );
        require(rewardEligibleAddresses.length > 0, "No eligible addresses");

        uint256 rewardPool = (balanceOf(address(this)) * 2) / 100;
        require(rewardPool > minRewardAmount, "Insufficient reward pool");
        require(balanceOf(address(this)) >= rewardPool, "Not enough tokens in contract");

        uint256 count = 0;
        for (uint256 i = 0; i < rewardEligibleAddresses.length && count < batchSize; i++) {
            address holder = rewardEligibleAddresses[i];
            if (isRewardEligible[holder] && balanceOf(holder) > 0) {
                uint256 rewardAmount = (rewardPool * balanceOf(holder)) / totalSupply();
                if (balanceOf(address(this)) < rewardAmount) {
                    break;
                }
                _transfer(address(this), holder, rewardAmount);
                count++;
            }
        }

        lastRewardDistribution = block.timestamp;
        emit RewardDistributed(rewardPool);
    }

    // ========== DAO Voting ==========
    function createProposal(string memory description, uint256 duration) external onlyOwner {
        proposals.push(Proposal(description, 0, block.timestamp, duration, false));
    }

    function vote(uint256 proposalId) external {
        require(balanceOf(msg.sender) > 0, "Must own tokens");
        require(!hasVoted[msg.sender][proposalId].voted, "Already voted");
        require(
            block.timestamp <= proposals[proposalId].startTime + proposals[proposalId].duration,
            "Voting period ended"
        );

        uint256 weight = (balanceOf(msg.sender) * (block.timestamp - lastTransactionTimestamp[msg.sender]))
            / (10**decimals());

        if (weight > maxVotePower) {
            weight = maxVotePower;
        }

        proposals[proposalId].voteCount += weight;
        hasVoted[msg.sender][proposalId] = VoteInfo(weight, true);

        emit VoteCast(msg.sender, proposalId, weight);
    }

    // ========== Secure Ownership ==========

    function setTrustedOwner(address newOwner, bool status) external onlyOwner {
        trustedOwners[newOwner] = status;
    }

    function transferOwnershipSecure(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid address");
        require(trustedOwners[newOwner], "New owner not trusted");
        require(
            block.timestamp >= lastOwnershipTransferTime + ownershipTimelock,
            "Ownership transfer locked"
        );

        lastOwnershipTransferTime = block.timestamp;
        _transferOwnership(newOwner);
    }

    // ========== Liquidity Lock ==========

    function lockLiquidity(uint256 duration) external onlyOwner {
        require(duration >= minLockPeriod, "Lock period too short");
        liquidityUnlockTime = block.timestamp + duration;
    }

    function setLiquidityStatus(bool _enabled) external onlyOwner {
        require(block.timestamp >= liquidityUnlockTime, "Liquidity is still locked");
        liquidityEnabled = _enabled;
        emit LiquidityStatusChanged(_enabled);
    }
}
