// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ERC20Mock } from "../../test/mocks/ERC20Mock.sol";
import { DeployDSC } from "../../script/DeployDSC.sol";
import { HelperConfig } from "../../script/HelperConfig.sol";
import { DecentralizedStableCoin } from "../../src/DecentralizedStableCoin.sol";
import { DSCcore } from "../../src/DSCcore.sol";

contract HandlerTest is Test {
    DecentralizedStableCoin public dsc;
    DSCcore public dscCore;
    HelperConfig public config;

    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint64 public constant MAX_DEPOSITORS = type(uint64).max;
    uint256 public countMinted;
    address[] public depositedUsers;

    constructor(DSCcore _dscCore, DecentralizedStableCoin _dsc) {
        dscCore = _dscCore;
        dsc = _dsc;

        address[] memory tokens = dscCore.getCollateralTokens();
        weth = ERC20Mock(tokens[0]);
        wbtc = ERC20Mock(tokens[1]);
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }

    function mintDsc(uint256 amount, uint256 userSeed) public {
        if (depositedUsers.length == 0) {
            return;
        }
        address sender = depositedUsers[userSeed % depositedUsers.length];
        vm.startPrank(sender);
        (, uint256 collateralValueInUsd) = dscCore.getAccountInformation();
        console.log("[collateralValueInUsd]: ", collateralValueInUsd);
        uint256 totalDscMinted = (collateralValueInUsd / 4);
        vm.assume(totalDscMinted > 0);
        amount = bound(amount, 1, totalDscMinted);
        vm.stopPrank();

        vm.prank(address(dscCore));
        dsc.mint(sender, amount);
        countMinted++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        amount = bound(amount, 1, MAX_DEPOSITORS);
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        address owner = msg.sender;
        vm.startPrank(owner);
        collateral.mint(owner, amount);
        collateral.approve(address(dscCore), amount);
        dscCore.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        depositedUsers.push(owner);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amount) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        address owner = msg.sender;
        uint256 collateralBalance = dscCore.getCollateralBalanceOf(owner, address(collateral));
        // If the balance is 0, the fuzzer will keep this fuzzing
        vm.assume(collateralBalance > 0);
        uint256 redeemAmount = bound(amount, 1, collateralBalance);

        vm.startPrank(owner);
        dscCore.redeemCollateral(address(collateral), redeemAmount);
        vm.stopPrank();
    }
}
