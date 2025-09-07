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
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc) =
            helperConfig.activeNetworkConfig();

        uint256 deployerKey = helperConfig.DEPLOYER_KEY();
        tokenAddrs = [wbtc, weth];
        priceFeedAddrs = [wbtcUsdPriceFeed, wethUsdPriceFeed];

        DecentralizedStableCoin dsc;
        DSCcore dscCore;

        if (block.chainid == 31_337) {
            address owner = msg.sender;
            vm.startPrank(owner);
            (dsc, dscCore) = deployContracts(owner);
            vm.stopPrank();
        } else {
            vm.startBroadcast(deployerKey);
            (dsc, dscCore) = deployContracts(msg.sender);
            vm.stopBroadcast();
        }
        return (dsc, dscCore, helperConfig);
    }

    function deployContracts(address owner) public returns (DecentralizedStableCoin, DSCcore) {
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(owner, "Decentralized Stable Coin", "DSC");
        DSCcore dscCore = new DSCcore(tokenAddrs, priceFeedAddrs, address(dsc));
        dsc.transferOwnership(address(dscCore));
        return (dsc, dscCore);
    }
}
