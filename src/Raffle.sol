//SPDX-License-Identifier:MIT
/**
 * @title Smart Contract Lottery: Raffle Game
 * @author Suyash Agrawal
 * @notice A fully Decentralized and randomised Raffle Lottery Generator
 * @dev Implements Chainlink VRFv2.5
 */
pragma solidity 0.8.19;
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract Raffle is VRFConsumerBaseV2Plus {
    error Raffle__SendMoreEth();
    error Raffle__TransferFailed();
    error Raffle__CanNotEnterRaffle();
    error Raffle__UpKeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );

    enum RaffleState {
        OPEN,
        CALCULATING
    }

    uint32 private constant NUM_WORDS = 1;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint256 private immutable i_EntranceFee;
    uint256 private immutable i_interval;
    uint256 private immutable i_subscriptionId;
    bytes32 private immutable i_keyHash;
    uint256 private s_lastTimeStamp;
    address payable[] public s_players;
    address private s_recentWinner;
    uint32 private immutable i_callbackGasLimit;

    /*Events*/

    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);

    RaffleState private s_RaffleState;

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        uint256 subscriptionId,
        bytes32 gasLane,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_EntranceFee = entranceFee;
        i_subscriptionId = subscriptionId;
        i_keyHash = gasLane;
        i_interval = interval;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_RaffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        if (msg.value < i_EntranceFee) {
            revert Raffle__SendMoreEth();
        }
        if (s_RaffleState != RaffleState.OPEN) {
            revert Raffle__CanNotEnterRaffle();
        }
        s_players.push(payable(msg.sender));
        emit RaffleEntered(msg.sender);
    }

    /**
     * @dev This function returns a bool UpKeepNeeded Which triggers the request to generate a random winner for the lottery as per the conditions :
     * 1.Sufficient time has Passed between the starting and end of the lottery.
     * 2.The Raffle is in a Open State.
     * 3.The Raffle Owner has gained sufficient entries and hence has ETH balance.
     * 4.Implicitly, our subscription has LINK.
     * @param - ignored
     * @return UpKeepNeeded
     * @return - ignored
     */

    function checkUpKeep(
        bytes memory /*checkData*/
    ) public view returns (bool UpKeepNeeded, bytes memory /*performData*/) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = s_RaffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        UpKeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (UpKeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool UpKeepNeeded, ) = checkUpKeep("");
        if (!UpKeepNeeded) {
            revert Raffle__UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_RaffleState)
            );
        }
        s_RaffleState = RaffleState.CALCULATING;
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] calldata randomWords
    ) internal virtual override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_RaffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(s_recentWinner);
    }

    //Getters

    function getEntranceFee() external view returns (uint256) {
        return i_EntranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return (s_RaffleState);
    }

    function getPlayer(uint256 IndexOfPlayer) external view returns (address) {
        return s_players[IndexOfPlayer];
    }

    function getLastTimeStamp() external view returns(uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns(address) {
        return s_recentWinner;
    }
}
