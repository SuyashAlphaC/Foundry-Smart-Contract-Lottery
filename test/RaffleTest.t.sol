//SPDX-License-Identifier:MIT

pragma solidity 0.8.19;
import {Test} from "forge-std/Test.sol";
import {Raffle} from "src/Raffle.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, CodeConstants {
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);

    Raffle public raffle;
    HelperConfig public helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    uint256 subscriptionId;
    bytes32 gasLane;
    uint32 callbackGasLimit;

    address public Player = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        subscriptionId = config.subscriptionId;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        vm.deal(Player, STARTING_BALANCE);
    }

    function testRaffleOpenwithOpen() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testCantEnterRaffleWithoutSendingEnough() public {
        vm.prank(Player);
        vm.expectRevert(Raffle.Raffle__SendMoreEth.selector);
        raffle.enterRaffle();
    }

    function testRaffleUpdatesThePlayerArray() public {
        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();
        address rafflePlayer = raffle.getPlayer(0);
        assertEq(Player, rafflePlayer);
    }

    function testEnteringRaffleTriggersEvent() public {
        vm.prank(Player);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(Player);

        raffle.enterRaffle{value: entranceFee}();
    }

    function testRaffleDoesNotAllowEnterWhenCalculating() public {
        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__CanNotEnterRaffle.selector);
        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpKeepGivesFalseWithNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool UpKeepNeeded, ) = raffle.checkUpKeep("");
        assert(!UpKeepNeeded);
    }

    function testCheckUpKeepNotWorkWithNotOpenState() public {
        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        (bool UpKeepNeeded, ) = raffle.checkUpKeep("");

        assert(!UpKeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    // Challenge 2. testCheckUpkeepReturnsTrueWhenParametersGood
    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        // Arrange
        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");

        // Assert
        assert(upkeepNeeded);
    }

    function testPerformUpKeepDoesNotWorkIfCheckUpKeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpKeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    modifier enteredRaffle() {
        vm.prank(Player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        _;
    }

    modifier skipfork() {
        if (block.chainid != ETH_LOCALHOST_CHAINID) {
            return;
        }
        _;
    }

    function testPerformUpKeepWorksCorrectlyAndEmitsRequestId()
        public
        enteredRaffle
    {
        vm.recordLogs();

        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState rState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);

        assert(uint256(rState) == 1);
    }

    function testFulFillRandomWordsCanOnlyBeCalledAfterRequestId(
        uint256 RequestRandomWords
    ) public enteredRaffle skipfork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            RequestRandomWords,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        enteredRaffle
        skipfork
    {
        address expectedWinner = address(1);

        // Arrange
        uint256 additionalEntrances = 3;
        uint256 startingIndex = 1; // We have starting index be 1 so we can start with address(1) and not address(0)

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrances;
            i++
        ) {
            address player = address(uint160(i));
            hoax(player, 1 ether); // deal 1 eth to the player
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 requestId = entries[1].topics[1]; // get the requestId from the logs

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrances + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
