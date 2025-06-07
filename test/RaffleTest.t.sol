// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../src/Raffle.sol";
import {DeployRaffle} from "../script/DeployRaffle.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

contract RaffleTest is Test {
    /* Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfigByChainId(block.chainid);
        link = config.link;
        callbackGasLimit = config.callbackGasLimit;
        interval = config.automationUpdateInterval;
        gasLane = config.gasLane;
        vrfCoordinator = config.vrfCoordinatorV2_5;
        entranceFee = config.raffleEntranceFee;
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    modifier anvilConfigured() {
        subscriptionId = VRFCoordinatorV2_5Mock(vrfCoordinator).createSubscription();
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(subscriptionId, address(raffle));
        VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(subscriptionId, (3 ether) * 100);
        _;
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /////////////////////////
    // enterRaffle         //
    /////////////////////////

    function testRaffleRevertsWHenYouDontPayEnoughFee() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    /////////////////////////
    // checkUpkeep         //
    /////////////////////////

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public anvilConfigured {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public anvilConfigured {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    /////////////////////////
    // performUpkeep       //
    /////////////////////////

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public anvilConfigured {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    /////////////////////////
    // Getter Functions    //
    /////////////////////////

    function testGetEntranceFee() public view {
        uint256 expectedEntranceFee = 0.01 ether;
        assert(raffle.getEntranceFee() == expectedEntranceFee);
    }

    function testGetRaffleState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testGetNumWords() public view {
        assert(raffle.getNumWords() == 1);
    }

    function testGetRequestConfirmations() public view {
        assert(raffle.getRequestConfirmations() == 3);
    }

    function testGetInterval() public view {
        assert(raffle.getInterval() == interval);
    }

    function testGetNumberOfPlayers() public {
        assert(raffle.getNumberOfPlayers() == 0);

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        assert(raffle.getNumberOfPlayers() == 1);
    }

    function testGetRaffleId() public view {
        assert(raffle.getRaffleId() == 0);
    }

    function testGetOwner() public view {
        assert(raffle.getOwner() != address(0));
    }

    /////////////////////////
    // Edge Cases          //
    /////////////////////////

    function testMultiplePlayersCanEnter() public {
        // Arrange
        address player1 = makeAddr("player1");
        address player2 = makeAddr("player2");
        address player3 = makeAddr("player3");

        vm.deal(player1, STARTING_USER_BALANCE);
        vm.deal(player2, STARTING_USER_BALANCE);
        vm.deal(player3, STARTING_USER_BALANCE);

        // Act
        vm.prank(player1);
        raffle.enterRaffle{value: entranceFee}();

        vm.prank(player2);
        raffle.enterRaffle{value: entranceFee}();

        vm.prank(player3);
        raffle.enterRaffle{value: entranceFee}();

        // Assert
        assert(raffle.getNumberOfPlayers() == 3);
        assert(raffle.getPlayer(0) == player1);
        assert(raffle.getPlayer(1) == player2);
        assert(raffle.getPlayer(2) == player3);
    }

    function testRafflePoolTracking() public {
        // Arrange
        uint256 currentRaffleId = raffle.getRaffleId();

        // Act
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Assert
        assert(raffle.getRaffleIdToPool(currentRaffleId) == entranceFee);
    }

    function testPlayerCanEnterMultipleTimes() public {
        // Act
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        raffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();

        // Assert
        assert(raffle.getNumberOfPlayers() == 2);
        assert(raffle.getPlayer(0) == PLAYER);
        assert(raffle.getPlayer(1) == PLAYER);
    }

    /////////////////////////
    // Fuzz Tests          //
    /////////////////////////

    function testFuzzEntranceFeeAmount(uint256 amount) public {
        // Arrange
        vm.assume(amount < entranceFee);
        vm.deal(PLAYER, amount);

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: amount}();
    }

    function testFuzzMultipleEntries(uint8 numPlayers) public {
        // Arrange
        vm.assume(numPlayers > 0 && numPlayers <= 100);

        // Act
        for (uint8 i = 0; i < numPlayers; i++) {
            address player = address(uint160(i + 1));
            vm.deal(player, STARTING_USER_BALANCE);
            vm.prank(player);
            raffle.enterRaffle{value: entranceFee}();
        }

        // Assert
        assert(raffle.getNumberOfPlayers() == numPlayers);
    }
}
