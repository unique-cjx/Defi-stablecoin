// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import { DeployDSC } from "../../script/DeployDSC.sol";
import { HelperConfig } from "../../script/HelperConfig.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCcore } from "../../src/DSCcore.sol";

import { MockV3Aggregator } from "../../test/mocks/MockV3Aggregator.sol";
import { ERC20Mock } from "../../test/mocks/ERC20Mock.sol";
import { MockFailedMintDSC } from "../../test/mocks/MockFailedMintDSC.sol";
import { MockFailedTransferERC20 } from "../../test/mocks/MockFailedTransferERC20.sol";
import { MockMoreDebtDSC } from "../../test/mocks/MockMoreDebtDSC.sol";

contract DSCcoreTest is Test {
    // DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCcore public dscCore;
    HelperConfig public config;

    address public wethUsdPriceFeed;
    address public wbtcUsdPriceFeed;
    address public weth;
    address public wbtc;

    address public testUser = makeAddr("user");
    uint256 public constant AMOUNT_MINTED_DSC = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 20 ether;

    address public liquidator = makeAddr("liquidator");

    /// SetUp before running all of tests
    function setUp() external {
        DeployDSC deployer = new DeployDSC();

        (dsc, dscCore, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(testUser, 100 ether);
        ERC20Mock(wbtc).mint(testUser, 10 ether);

        ERC20Mock(weth).mint(liquidator, 100 ether);
        ERC20Mock(wbtc).mint(liquidator, 10 ether);
    }

    /// Modifiers
    modifier depositCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_MINTED_DSC);
        dscCore.depositCollateral(weth, AMOUNT_MINTED_DSC);
        vm.stopPrank();
        _;
    }

    modifier depositAndMintCollateral() {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_COLLATERAL);
        uint256 dscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC);
        dscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, dscAmount);
        vm.stopPrank();
        _;
    }

    modifier liquidate() {
        uint256 dscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC);

        vm.startPrank(testUser);
        // deposit more collateral to trigger liquidation, since you need to pay a bit of rewards to liquidator
        uint256 amountToDeposit = AMOUNT_COLLATERAL + 1 ether;
        ERC20Mock(weth).approve(address(dscCore), amountToDeposit);
        dsc.approve(address(dscCore), dscAmount);
        dscCore.depositCollateralAndMint(weth, amountToDeposit, dscAmount);

        uint256 redeemAmount = AMOUNT_COLLATERAL / 2;
        dscCore.redeemCollateral(weth, redeemAmount);

        uint256 badHealthFactor = dscCore.calculateHealthFactor(dscAmount, getValueOfWethInUsd(redeemAmount + 1 ether));
        assertLt(badHealthFactor, dscCore.getMinHealthFactor());
        vm.stopPrank();

        dscAmount = getValueOfWethInUsd(50 ether);
        vm.prank(address(dscCore));
        dsc.mint(liquidator, dscAmount);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscCore), 100 ether);
        dsc.approve(address(dscCore), dscAmount);
        vm.stopPrank();
        _;
    }

    /// Common function for all tests

    function getValueOfWethInUsd(uint256 amountCollateral) public view returns (uint256) {
        (, int256 wethPrice,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        // if amountCollateral is 10e18(10 ether)
        // 4_000e8 * 1e10 = 4_000e18
        uint256 collateralValueInUsd = uint256(wethPrice) * dscCore.getAdditionalFeedPrecision();
        // 4_000e18 * 10e18 = 40_000e36 / 1e18 = 40_000e18
        uint256 amountToMint = (collateralValueInUsd * amountCollateral) / dscCore.getPrecision();
        return amountToMint;
    }

    /// Constructor tests
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

    function testDepositCollateral() external {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(testUser, AMOUNT_MINTED_DSC);

        vm.expectRevert(DSCcore.DSCcore__MustBeMoreThanZero.selector);
        dscCore.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsUnApprovedCollateral() external {
        ERC20Mock roseToken = new ERC20Mock("Rose Token", "ROSE", testUser, AMOUNT_MINTED_DSC);
        vm.startPrank(testUser);
        vm.expectRevert(DSCcore.DSCcore__NotAllowedToken.selector);
        dscCore.depositCollateral(address(roseToken), AMOUNT_MINTED_DSC);
        vm.stopPrank();
    }

    function testDepositWithoutMinting() public depositCollateral {
        uint256 dscBalance = dsc.balanceOf(testUser);
        assertEq(dscBalance, 0);
    }

    function testDepositAndGetAccountInformation() public depositCollateral {
        vm.startPrank(testUser);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscCore.getAccountInformation();
        assertEq(totalDscMinted, 0);
        // the amount of weth is 10, each price is $4,000
        assertEq(collateralValueInUsd, 40_000e18);
        vm.stopPrank();
    }

    function testRevertIfMintedDscBreaksHealthFactor() public {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_MINTED_DSC);
        uint256 wethValueInUSD = getValueOfWethInUsd(AMOUNT_MINTED_DSC);
        uint256 dscAmount = wethValueInUSD;
        uint256 badHealthFactor = dscCore.calculateHealthFactor(dscAmount, wethValueInUSD);
        assertEq(badHealthFactor, 0.5e18);

        // CollateralThreshold = (40_000e18 * 50) / 100 = 20_000e18
        // HealthFactor = (CollateralThreshold / DSCAmount) = 0.5 < 1, thus revert
        vm.expectRevert(abi.encodeWithSelector(DSCcore.DSCcore__HealthFactorBelowOne.selector, badHealthFactor));
        dscCore.depositCollateralAndMint(weth, AMOUNT_MINTED_DSC, dscAmount);
        vm.stopPrank();
    }

    function testDepositAndMintCollateral() public depositAndMintCollateral {
        uint256 dscBalance = dsc.balanceOf(testUser);
        assertEq(dscBalance, getValueOfWethInUsd(AMOUNT_MINTED_DSC));
    }

    /// Minting DSC tests

    function testRevertsIfMintFails() public {
        address[] memory tokenAddrs = new address[](1);
        address[] memory priceFeedAddrs = new address[](1);
        tokenAddrs[0] = weth;
        priceFeedAddrs[0] = wethUsdPriceFeed;

        address owner = msg.sender;
        MockFailedMintDSC mockDsc = new MockFailedMintDSC(owner, "Mock Failed Mint DSC", "mDSC");
        DSCcore mockDscCore = new DSCcore(tokenAddrs, priceFeedAddrs, address(mockDsc));
        // useing true owner to transfer ownership
        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscCore));

        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(mockDscCore), AMOUNT_COLLATERAL);

        uint256 dscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC);
        vm.expectRevert(DSCcore.DSCcore__MintFailed.selector);
        mockDscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, dscAmount);
        vm.stopPrank();
    }

    function testRevertIfMintAmountIsZero() public {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_COLLATERAL);
        dscCore.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.expectRevert(DSCcore.DSCcore__MustBeMoreThanZero.selector);
        dscCore.mintDsc(0);
        vm.stopPrank();
    }

    /// Burning DSC tests

    function testRevertBurnIfMoreThanUserHas() public {
        vm.startPrank(testUser);
        vm.expectRevert(DSCcore.DSCcore__BurnAmountExceedsBalance.selector);
        dscCore.burnDsc(1);
        vm.stopPrank();
    }

    function testBurnDsc() public depositAndMintCollateral {
        vm.startPrank(testUser);
        uint256 dscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC);
        assertEq(dsc.balanceOf(testUser), dscAmount);
        // Approve DSCcore to spend user's DSC before burning
        dsc.approve(address(dscCore), dscAmount);
        dscCore.burnDsc(dscAmount);
        // Check that the user's DSC balance is now 0 after burning
        assertEq(dsc.balanceOf(testUser), 0);
        vm.stopPrank();
    }

    /// Redeems DSC tests

    function testRedeemCollateral() public {
        vm.startPrank(testUser);

        ERC20Mock(weth).approve(address(dscCore), AMOUNT_COLLATERAL);
        dsc.approve(address(dscCore), AMOUNT_MINTED_DSC);

        uint256 dscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC);
        dscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, dscAmount);
        (, uint256 collateralValueInUsd) = dscCore.getAccountInformation();
        // each weth price is $4,000 or 4000e18
        // 4000e18 * 20e18 / 1e18 = 80_000e18
        assertEq(collateralValueInUsd, 80_000e18);

        dscCore.redeemCollateral(weth, AMOUNT_COLLATERAL);
        (, collateralValueInUsd) = dscCore.getAccountInformation();
        assertEq(collateralValueInUsd, 0);

        vm.stopPrank();
    }

    function testRevertRedeemIfTransferFails() public {
        MockFailedTransferERC20 rose = new MockFailedTransferERC20();

        address[] memory tokenAddrs = new address[](1);
        address[] memory priceFeedAddrs = new address[](1);
        tokenAddrs[0] = address(rose);
        priceFeedAddrs[0] = wethUsdPriceFeed;
        DSCcore mockDscCore = new DSCcore(tokenAddrs, priceFeedAddrs, address(dsc));

        vm.prank(address(dscCore));
        dsc.transferOwnership(address(mockDscCore));

        vm.startPrank(testUser);
        MockFailedTransferERC20(rose).mint(testUser, 100 ether);
        MockFailedTransferERC20(rose).approve(address(mockDscCore), AMOUNT_COLLATERAL);

        uint256 dscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC);
        // Deposit ROSE collateral and mint DSC
        mockDscCore.depositCollateralAndMint(address(rose), AMOUNT_COLLATERAL, dscAmount);
        assertEq(dsc.balanceOf(testUser), dscAmount);

        // Redeem ROSE collateral
        vm.expectRevert(DSCcore.DSCcore__TransferFailed.selector);
        mockDscCore.redeemCollateral(address(rose), AMOUNT_COLLATERAL);

        vm.stopPrank();
    }

    /// Liquidation tests

    function testRevertLiquidationHealthFactorAboveMinimum() public {
        vm.startPrank(testUser);
        ERC20Mock(weth).approve(address(dscCore), AMOUNT_COLLATERAL);

        uint256 valueInUSD = getValueOfWethInUsd(AMOUNT_COLLATERAL);
        uint256 dscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC);

        dscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL, dscAmount);
        assertEq(dsc.balanceOf(testUser), dscAmount);
        vm.stopPrank();

        uint256 normalHealthFactor = dscCore.calculateHealthFactor(dscAmount, valueInUSD);
        assertEq(normalHealthFactor, 1e18);

        vm.startPrank(liquidator);
        vm.expectRevert(abi.encodeWithSelector(DSCcore.DSCcore__HealthFactorAboveMinimum.selector, normalHealthFactor));
        dscCore.liquidate(weth, testUser, dscAmount);
        vm.stopPrank();
    }

    function testReverLiquidationtHealthFactorNotImprovedOnLiquidation() public {
        address[] memory tokenAddrs = new address[](1);
        address[] memory priceFeedAddrs = new address[](1);
        tokenAddrs[0] = weth;
        priceFeedAddrs[0] = wethUsdPriceFeed;

        address owner = msg.sender;
        MockMoreDebtDSC mockDsc = new MockMoreDebtDSC(wethUsdPriceFeed, owner, "Mock More Debt DSC", "mDSC");
        DSCcore mockDscCore = new DSCcore(tokenAddrs, priceFeedAddrs, address(mockDsc));

        vm.prank(owner);
        mockDsc.transferOwnership(address(mockDscCore));

        vm.startPrank(testUser);
        // set up account with testUser
        uint256 dscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC);
        ERC20Mock(weth).approve(address(mockDscCore), AMOUNT_COLLATERAL + 5 ether);
        mockDsc.approve(address(mockDscCore), dscAmount);

        mockDscCore.depositCollateralAndMint(weth, AMOUNT_COLLATERAL + 5 ether, dscAmount);
        vm.stopPrank();

        vm.prank(address(mockDscCore));
        mockDsc.mint(liquidator, dscAmount * 2);

        // cut WETH price in half
        // now the testUser's health factor is below minHealthFactor
        // and which means testUser is eligible for liquidation
        // he has 25 weth as collateral, worth is 25eth*$2,000 = $50,000, minted 40,000 DSC
        (, int256 updatedWethPrice,,,) = MockV3Aggregator(wethUsdPriceFeed).latestRoundData();
        updatedWethPrice = updatedWethPrice / 2;
        MockV3Aggregator(wethUsdPriceFeed).updateAnswer(updatedWethPrice);

        vm.startPrank(liquidator);
        // fix minted DSC amount: 20,000 - 2,000 = 18,000 DSC
        // 1.eth amount: 18,000 / 2,000 = 9 eth
        // 2.rewards: (9 * 10) / 100 = 0.9 eth
        uint256 fixedDscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC - 1 ether);
        ERC20Mock(weth).approve(address(mockDscCore), AMOUNT_COLLATERAL);
        mockDsc.approve(address(mockDscCore), fixedDscAmount);

        vm.expectRevert(DSCcore.DSCcore__HealthFactorNotImproved.selector);
        mockDscCore.liquidate(weth, testUser, fixedDscAmount);

        vm.stopPrank();
    }

    function testLiquidationCorrectRewards() public liquidate {
        vm.startPrank(liquidator);
        // set up assets of liquidator
        uint256 liquidatorDscBalance = dsc.balanceOf(liquidator);
        uint256 liquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);

        // the starting collateral value is 20 weth, it is worth $80,000, minted 40,000 DSC
        // redeem half of collateral is 10 weth, after that is worth $40,000
        // so the testUser's latest health factor is 0.5
        // to make health factor back to 1, liquidator need to pay debt which is minted 40,000 DSC

        uint256 fixedDscAmount = getValueOfWethInUsd(AMOUNT_MINTED_DSC);
        dscCore.liquidate(weth, testUser, fixedDscAmount);

        uint256 wethAmount = dscCore.getTokenAmountFromUsd(weth, fixedDscAmount);
        uint256 rewardWeths = (wethAmount * dscCore.getLiquidationBonus()) / dscCore.getLiquidationPrecision();
        rewardWeths = rewardWeths + wethAmount;

        uint256 latestLiquidatorDscBalance = dsc.balanceOf(liquidator);
        uint256 latestLiquidatorWethBalance = ERC20Mock(weth).balanceOf(liquidator);

        assertEq(latestLiquidatorDscBalance, liquidatorDscBalance - fixedDscAmount);
        assertEq(latestLiquidatorWethBalance, liquidatorWethBalance + rewardWeths);

        vm.stopPrank();
    }
}
