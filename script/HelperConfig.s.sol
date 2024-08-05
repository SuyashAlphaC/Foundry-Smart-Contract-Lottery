//SPDX-License-Identifier:MIT

pragma solidity 0.8.19;
import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

abstract contract CodeConstants {
    /* VRF MOCK VALUES*/
    uint96 public constant MOCK_BASE_FEE = 0.25 ether;
    uint96 public constant MOCK_GAS_PRICE = 1e9;
    int256 public constant MOCK_WEI_PER_UINT_LINK = 4e15;

    uint256 public constant ETH_SEPOLIA_CHAINID = 11155111;
    uint256 public constant ETH_LOCALHOST_CHAINID = 31337;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        uint256 entranceFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 gasLane;
        uint32 callbackGasLimit;
        uint256 subscriptionId;
        address link;
        address account;
    }

    mapping(uint256 chainid => NetworkConfig) public networkConfigs;
    NetworkConfig public localNetworkConfig;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAINID] = getSepoliaNetworkConfig();
    }

    function getConfigByChainid(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (networkConfigs[chainId].vrfCoordinator != address(0)) {
            return networkConfigs[chainId];
        } else if (chainId == ETH_LOCALHOST_CHAINID) {
            return getOrCreateAnvilNetworkConfig();
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getConfigByChainid(block.chainid);
    }

    function getSepoliaNetworkConfig()
        public
        pure
        returns (NetworkConfig memory)
    {
        return
            NetworkConfig(
                0.01 ether,
                30,
                0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
                0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                500000,
                46672112515486664947392791248667704544846171461627657629430596254360608515055,
                0x779877A7B0D9E8603169DdbD7836e478b4624789,
                0xC29504f0E7fcff92Cd5E9231241aDfC5a17Dc5Ef
            );
    }

    function getOrCreateAnvilNetworkConfig()
        public
        returns (NetworkConfig memory)
    {
        if (localNetworkConfig.vrfCoordinator != address(0)) {
            return localNetworkConfig;
        } else {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock vrfCoordinatorMock = new VRFCoordinatorV2_5Mock(
                    MOCK_BASE_FEE,
                    MOCK_GAS_PRICE,
                    MOCK_WEI_PER_UINT_LINK
                );
            LinkToken linkToken = new LinkToken();
            vm.stopBroadcast();

            localNetworkConfig = NetworkConfig(
                0.01 ether,
                30,
                address(vrfCoordinatorMock),
                0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                500000,
                0,
                address(linkToken),
                0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38
            );
            return localNetworkConfig;
        }
    }
}
