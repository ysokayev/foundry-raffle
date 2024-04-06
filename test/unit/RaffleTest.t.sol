// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /**Events */

    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordiantor;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrfCoordiantor,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();
        (, , , , , , , deployerKey) = helperConfig.activeNetworkConfig();

        vm.deal(PLAYER, STARING_USER_BALANCE);
    }

    function testRafffleInitializedInOpenStat() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    ////////////////////////
    /** Enter Raffle */

    function testRaffleRevertWhenNotEnoughEth() public {
        //Arange
        vm.prank(PLAYER);
        //Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerEntry() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventsOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterClosedRaffle() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    ////////////////
    //checkUpKeep///
    ////////////////

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        //assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        //Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(upkeepNeeded == false);
    }

    //testCheckUpkeepTurnsFalseIfEnoughTimeNotPassed
    function testCheckUpkeepTurnsFalseIfEnoughTimeNotPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    //testCHeckUpkeepReturnsTrueWhenParametersAreGood

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    ////////////////
    //checkUpKeep///
    ////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkkeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Accountr
        raffle.performUpkeep("");
        // (, bytes memory randomWords) = raffle.fulfillRandomWords();
        // assert(randomWords[0] != 0);
    }

    function testPerformUpkeepReversIfCheckUpkeepIsFalse() public {
        //Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;

        //Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    // What if i need to test using the output of an event, events are not accessible by smart contracts. Chainlink is listening to the requestRandomWords event.
    modifier raffleEnteredAndTImePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdateRaffleStateAndEmitRequestId()
        public
        raffleEnteredAndTImePassed
    {
        //Arrange

        //Act
        vm.recordLogs();
        raffle.performUpkeep(""); //emmit the requestId
        //Assert
        Vm.Log[] memory entires = vm.getRecordedLogs();
        bytes32 requestId = entires[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    ///////////////////////
    //fulfillRandomWords///
    ///////////////////////

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId //foundry will call many numbers for randomRequestId "fuzz test"
    ) public raffleEnteredAndTImePassed skipFork {
        //Arrange
        vm.expectRevert("nonexistent request"); //error in bash will return "nonexistent request" if non is provided
        VRFCoordinatorV2Mock(vrfCoordiantor).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        raffleEnteredAndTImePassed
        skipFork
    {
        //Arrange
        uint256 additionalEntrance = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrance;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, STARING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        // get requestId

        uint256 prize = entranceFee * (additionalEntrance + 1);

        vm.recordLogs();
        raffle.performUpkeep(""); //emmit the requestId
        //Assert
        Vm.Log[] memory entires = vm.getRecordedLogs();
        bytes32 requestId = entires[1].topics[1];

        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        // pretend to be chainlink vrf to get the random number and get the winner
        VRFCoordinatorV2Mock(vrfCoordiantor).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(address(raffle.getRecentWinner()) != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(previousTimeStamp < raffle.getLastTimeStamp());
        assert(
            raffle.getRecentWinner().balance ==
                prize + STARING_USER_BALANCE - entranceFee
        );
    }
}
