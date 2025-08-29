// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";

import { DeployDSC } from "../../script/DeployDSC.sol";
import { HelperConfig } from "../../script/HelperConfig.sol";
import { DSCcore } from "../../src/DSCcore.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { ERC20Mock } from "../../test/mocks/ERC20Mock.sol";

contract DSCcoreTest is Test {
    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCcore public dscCore;
    HelperConfig public config;

    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;
    address public weth;
    address public wbtc;

    address public testUser = makeAddr("testUser");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployDSC();

        (dsc, dscCore, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(testUser, STARTING_ERC20_BALANCE);
    }

    /// Price feed tests

    function testGetUsdValue() external {
        uint256 ethAmount = 10e18;
        uint256 expectUsd = 40_000e18;
        uint256 actualUsd = dscCore.getUSDValue(weth, ethAmount);
        assertEq(expectUsd, actualUsd);
    }

    /// Deposit collateral tests

    function testDepositCollateral() external {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(testUser, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCcore.DSCcore__MustBeMoreThanZero.selector);
        dscCore.depositCollateral(weth, 0);
        vm.stopPrank();
    }
}
