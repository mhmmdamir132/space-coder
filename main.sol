// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Space Coder
/// @notice Orbital mission ledger for on-chain coding quest verification. Trajectory params and vault are fixed at deploy.
contract SpaceCoder {
    // -------------------------------------------------------------------------
    // Immutable config (set in constructor, never changed)
    // -------------------------------------------------------------------------
    address public immutable missionVault;
    address public immutable trajectoryGuard;
    address public immutable rewardTreasury;
    uint256 public immutable genesisBlock;
    uint256 public immutable genesisTimestamp;
    uint256 public immutable maxMissionsPerCoder;
    uint256 public immutable cooldownBlocks;
    uint256 public immutable missionFeeWei;
    uint256 public immutable minDifficulty;
    uint256 public immutable maxDifficulty;
    bytes32 public immutable orbitDomain;

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------
    uint256 public totalMissionsLogged;
    uint256 public totalRewardsClaimed;
    bool public orbitPaused;
    uint256 private _locked;

    struct MissionRecord {
        uint256 missionId;
        uint256 loggedAt;
        uint8 difficultyTier;
        bool rewardClaimed;
        bytes32 questHash;
    }

    struct CoderStats {
        uint256 missionCount;
        uint256 lastMissionBlock;
        uint256 totalDifficultyScore;
    }

    mapping(address => MissionRecord[]) private _missionsByCoder;
    mapping(address => CoderStats) private _coderStats;
    mapping(bytes32 => bool) private _questHashUsed;
    mapping(address => uint256) public pendingRewards;

    // -------------------------------------------------------------------------
    // Constants (unique values, not reused from other contracts)
    // -------------------------------------------------------------------------
    uint256 public constant FEE_DENOMINATOR = 10_000;
    uint256 public constant REWARD_BASE_UNIT = 1e18;
    uint256 public constant MAX_DIFFICULTY_TIER = 10;
    uint256 public constant TRAJECTORY_WINDOW = 512;
    uint256 public constant PAUSE_GRACE_BLOCKS = 77;

    // -------------------------------------------------------------------------
    // Custom errors (unique names and messages)
    // -------------------------------------------------------------------------
    error TrajectoryDenied();
    error BurnRateExceeded();
    error OrbitPaused();
    error InvalidDifficultyTier();
    error CooldownActive();
    error ZeroTrajectory();
    error QuestHashAlreadyUsed();
    error MissionLimitReached();
    error NoPendingReward();
    error TransferFailed();
    error InvalidVault();
    error ReentrantCall();

    // -------------------------------------------------------------------------
    // Events (unique naming)
    // -------------------------------------------------------------------------
    event MissionLogged(
        address indexed coder,
        uint256 indexed missionId,
        uint8 difficultyTier,
        bytes32 questHash,
        uint256 totalMissions
    );
    event OrbitPauseToggled(bool paused);
    event RewardClaimed(address indexed coder, uint256 amount);
    event TrajectoryUpdated(address indexed guard, address newVault);
    event PendingRewardCredited(address indexed coder, uint256 amount);
    event FeeCollected(uint256 amount);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------
    modifier onlyTrajectoryGuard() {
        if (msg.sender != trajectoryGuard) revert TrajectoryDenied();
        _;
    }

    modifier onlyMissionVault() {
        if (msg.sender != missionVault) revert InvalidVault();
        _;
    }

    modifier whenOrbitNotPaused() {
        if (orbitPaused) revert OrbitPaused();
        _;
    }

    modifier nonReentrant() {
        if (_locked != 0) revert ReentrantCall();
        _locked = 1;
        _;
        _locked = 0;
    }

    // -------------------------------------------------------------------------
    // Constructor (all addresses and params populated; no caller input required)
    // -------------------------------------------------------------------------
    constructor() {
        missionVault = 0x7B3c9E2f1A4d6F8b0C2e5A7D9f1B3c5E7a9D1f;
        trajectoryGuard = 0x8C4d0F3a2B5e7D9f1A3c6E8b0D2f4A6c8E1a3;
        rewardTreasury = 0x9D5e1A4b3C6f8E0a2D4b6F8c0E2a4C6e8A1c3;
        genesisBlock = block.number;
        genesisTimestamp = block.timestamp;
        maxMissionsPerCoder = 120;
        cooldownBlocks = 5;
        missionFeeWei = 0.001 ether;
        minDifficulty = 1;
        maxDifficulty = 10;
        orbitDomain = keccak256(
            abi.encodePacked(
                block.chainid,
                address(this),
                "SpaceCoder_Orbit_v2",
                genesisTimestamp,
                block.prevrandao
            )
        );
    }

    // -------------------------------------------------------------------------
    // External: mission logging (anyone when not paused, subject to limits)
