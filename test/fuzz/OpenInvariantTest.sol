// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { DeployDSC } from "../../script/DeployDSC.sol";
import { HelperConfig } from "../../script/HelperConfig.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCcore } from "../../src/DSCcore.sol";
import { HandlerTest } from "./HandlerTest.sol";

contract OpenInvariantTest is Test {
    DecentralizedStableCoin public dsc;
    DSCcore public dscCore;
    HelperConfig public config;
    HandlerTest public handler;

    address public weth;
    address public wbtc;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();

        (dsc, dscCore, config) = deployer.run();
        (,, weth, wbtc) = config.activeNetworkConfig();
        handler = new HandlerTest(dscCore, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = ERC20(weth).balanceOf(address(dscCore));
        uint256 totalWBtcDeposited = ERC20(wbtc).balanceOf(address(dscCore));

        uint256 totalWethValueInUsd = dscCore.getUSDValue(weth, totalWethDeposited);
        uint256 totalBtcValueInUsd = dscCore.getUSDValue(wbtc, totalWBtcDeposited);
        assert(totalWethValueInUsd + totalBtcValueInUsd >= totalSupply);

        console.log("Weth total deposited", totalWethDeposited);
        console.log("Wbtc total deposited", totalWBtcDeposited);
        console.log("Total supply of DSC", totalSupply);
    }
}
