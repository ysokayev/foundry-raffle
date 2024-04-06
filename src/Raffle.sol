// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol"; //Raffle contract must be added as a consumer to the subscription
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol"; //Used to get the random number

/**
 * @title A Sample Raffle Contract
 * @author Yuriy Sokayev
 * @notice This contract is for creating a raffle
 * @dev Implements Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );

    //bool lotteryState = open, closed, calc
    /** Tyoe declarations */
    enum RaffleState {
        OPEN, //0
        CALCULATING //1
    } //2

    /** State Variables */

    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    // duration of lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    //** Events */

    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordiantor,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordiantor) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordiantor);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
    }

    function enterRaffle() public payable {
        // require(msg.value >= i_entranceFee, "Not enough ETH");
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /**
     * @dev This is the func that the CHainlink Auutomation nodes call to see if its time to perform an upleep.
     * The following should be true.
     * 1. The time interval has passed between raffle runs
     * 2. THe raffle is in the oopen state
     * 3. The contract has ETH
     * 4. The subscription is funded with LINK
     */
    function checkUpkeep(
        // checkUpkeep is called after enough time has passed
        bytes memory /* chckData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        // Called by Chainlink nodes
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING;
        //uint256 requestId = i_vrfCoordinator.requestRandomWords(
        uint256 requestId = i_vrfCoordinator.requestRandomWords( //Request to Chainlink node
            i_gasLane, //gas lane
            i_subscriptionId, // id funded with link
            REQUEST_CONFIRMATIONS, //block confirmations
            i_callbackGasLimit, //make sure not overspend
            NUM_WORDS // number of words
        ); //Chainlink is listening to the requestRandomWords event.
        emit RequestedRaffleWinner(requestId);
    }

    //** pickWinner is now performUpkeep*/
    // function pickWinner() external {
    //     if ((block.timestamp - s_lastTimeStamp) < i_interval) {
    //         revert();
    //     }
    //     s_raffleState = RaffleState.CALCULATING;
    //     uint256 requestId = i_vrfCoordinator.requestRandomWords(
    //         i_gasLane, //gas lane
    //         i_subscriptionId, // id funded with link
    //         REQUEST_CONFIRMATIONS, //block confirmations
    //         i_callbackGasLimit, //make sure not overspend
    //         NUM_WORDS // number of words
    //     );
    // }

    // CEI: checks, effects, interactions
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        //s_players = 10
        //rng 1226165486456156456465451123123123123
        //26165486456156456465451123123123123 % 10 = 2
        // checks
        // effects
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        emit PickedWinner(winner);
        //interactions
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Function */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
