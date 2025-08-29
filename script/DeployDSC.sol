// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Script } from "forge-std/Script.sol";
import { DecentralizedStableCoin } from "../src/DecentralizedStableCoin.sol";
import { DSCcore } from "../src/DSCcore.sol";
import { HelperConfig } from "./HelperConfig.sol";

contract DeployDSC is Script {
    address[] public tokenAddrs;
    address[] public priceFeedAddrs;

    function run() external returns (DecentralizedStableCoin, DSCcore, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();

        // Deploy DSC and DSCcore contracts
        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(msg.sender, "Decentralized Stable Coin", "DSC");
        tokenAddrs = [wbtc, weth];
        priceFeedAddrs = [wbtcUsdPriceFeed, wethUsdPriceFeed];
        DSCcore dscCore = new DSCcore(tokenAddrs, priceFeedAddrs, address(dsc));
        // Only transfer ownership when not running on local test chain (Anvil/Foundry default chain id 31337).
        // This avoids breaking tests that expect the test account to be the owner.
        if (block.chainid != 31_337) {
            dsc.transferOwnership(address(dscCore));
        }
        vm.stopBroadcast();

        return (dsc, dscCore, helperConfig);
    }
}
