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
