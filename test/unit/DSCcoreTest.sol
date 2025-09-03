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

    /// Constructor Tests

    function testConstructor() external {
        address[] memory tokenAddrs = new address[](2);
        address[] memory priceFeedAddrs = new address[](1);
        tokenAddrs[0] = weth;
        tokenAddrs[1] = wbtc;
        priceFeedAddrs[0] = wethUsdPriceFeed;
        vm.expectRevert(DSCcore.DSCcore__TokenAddressAndPriceFeedAddressLengthMustBeSame.selector);
        new DSCcore(tokenAddrs, priceFeedAddrs, address(dsc));
    }

    /// Price feed tests

    function testGetUsdValue() external {
        uint256 ethAmount = 10e18;
        uint256 expectUsd = 40_000e18;
        uint256 actualUsd = dscCore.getUSDValue(weth, ethAmount);
        assertEq(expectUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() external {
        // mock weth price is $4000
        uint256 usdAmount = 100e18;
        uint256 expectedWeth = 0.025e18;
        uint256 actualWeth = dscCore.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    /// Deposit collateral tests

    modifier depositeCollateral(uint256 mintDscAmount) {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_COLLATERAL);
        if (mintDscAmount > 0) {
            dscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, mintDscAmount);
        } else {
            dscCore.depositCollateral(weth, AMOUNT_COLLATERAL);
        }
        vm.stopPrank();
        _;
    }

    function testDepositCollateral() external {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(testUser, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCcore.DSCcore__MustBeMoreThanZero.selector);
        dscCore.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsUnApprovedCollateral() external {
        ERC20Mock roseToken = new ERC20Mock("Rose Token", "ROSE", testUser, AMOUNT_COLLATERAL);
        vm.startPrank(testUser);
        vm.expectRevert(DSCcore.DSCcore__NotAllowedToken.selector);
        dscCore.depositCollateral(address(roseToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testDepositAndGetAccountInformation() external depositeCollateral(0) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscCore.getAccountInformation();
        uint256 expectedTotalValueInUSD = dscCore.getAccountCollateralValue(testUser); // the amount of weth is 10, each
            // price is $4,000
        assertEq(totalDscMinted, 0);
        assertEq(40_000e18, expectedTotalValueInUSD);
    }
}
