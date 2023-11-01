// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {MistFarmingPool} from "../src/MistFarmingPool.sol";
import {ERC20} from "erc20-farming-pool/ERC20.sol";
import "forge-std/Test.sol";

contract WMSTFarmingPoolE2ETests is Test {
    MistFarmingPool public pool;

    ERC20 public constant WMST = ERC20(address(0x7Fd4d7737597E7b4ee22AcbF8D94362343ae0a79));
    ERC20 public constant WBTC = ERC20(address(0x476908D9f75687684CE3DBF6990e722129cDbCc6));

    address public immutable owner = address(0xC701E3D2DcCf4115D87a92f2a6E0eeEF2f0D0F25);
    address public immutable deployer = address(0xC7A7a14055c433399b89f2A3C70e3CaB70E97dEd);

    address user1 = vm.addr(1);
    address user2 = vm.addr(2);
    address user3 = vm.addr(3);

    uint256 constant START = 10_000;
    uint256 constant PERIOD = 365 * 4 * 1 days; // 4 years
    uint256 constant REWARD_AMOUNT = 1000e8;
    uint256 constant STAKE_AMOUNT = 1000e2;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_URL_MAINNET"));

        vm.startPrank(deployer);
        pool = new MistFarmingPool();
        vm.stopPrank();

        //deal rewards tokens to distributor
        deal(address(WBTC), owner, REWARD_AMOUNT);

        //deal staking tokens to users
        deal(address(WMST), user1, STAKE_AMOUNT);
        deal(address(WMST), user2, STAKE_AMOUNT);
        deal(address(WMST), user3, STAKE_AMOUNT);

        vm.warp(START);
    }

    function test_e2e() public {
        // initial state
        assertEq(pool.totalSupply(), 0);
        assertEq(pool.owner(), owner);
        assertEq(pool.name(), "WMST-WBTC Farming Pool");
        assertEq(pool.symbol(), "WMST-WBTC");
        assertEq(pool.decimals(), 2);
        assertEq(pool.distributor(), address(0));
        assertEq(pool.stakingToken(), address(WMST));
        assertEq(pool.rewardsToken(), address(WBTC));

        // set distributor
        vm.expectRevert();
        pool.setDistributor(deployer);
        vm.startPrank(owner);
        pool.setDistributor(owner);
        vm.stopPrank();
        assertEq(pool.distributor(), owner);

        // start farming
        vm.startPrank(owner);
        WBTC.approve(address(pool), REWARD_AMOUNT);
        pool.startFarming(REWARD_AMOUNT, PERIOD);
        vm.stopPrank();
        assertEq(pool.totalSupply(), 0);

        // user1 stakes
        vm.startPrank(user1);
        WMST.approve(address(pool), STAKE_AMOUNT);
        pool.deposit(STAKE_AMOUNT);
        vm.stopPrank();
        assertEq(pool.totalSupply(), STAKE_AMOUNT);
        assertEq(pool.balanceOf(user1), STAKE_AMOUNT);

        // user2 stakes
        vm.startPrank(user2);
        WMST.approve(address(pool), STAKE_AMOUNT);
        pool.deposit(STAKE_AMOUNT);
        vm.stopPrank();
        assertEq(pool.totalSupply(), STAKE_AMOUNT * 2);
        assertEq(pool.balanceOf(user2), STAKE_AMOUNT);

        // quarter of period passed
        vm.warp(START + PERIOD / 4);
        assertEq(pool.farmed(user1), REWARD_AMOUNT / 4 / 2);
        assertEq(pool.farmed(user2), REWARD_AMOUNT / 4 / 2);

        // emergency stop farming correctness
        uint256 snapshotId = vm.snapshot();
        vm.expectRevert();
        pool.stopFarming();
        vm.startPrank(owner);
        pool.stopFarming();
        vm.stopPrank();
        assertEq(pool.totalSupply(), STAKE_AMOUNT * 2);
        assertEq(pool.balanceOf(user1), STAKE_AMOUNT);
        assertEq(pool.balanceOf(user2), STAKE_AMOUNT);
        assertEq(pool.farmed(user1), REWARD_AMOUNT / 4 / 2);
        assertEq(pool.farmed(user2), REWARD_AMOUNT / 4 / 2);
        assertEq(WBTC.balanceOf(address(pool)), REWARD_AMOUNT / 4);
        assertEq(WBTC.balanceOf(owner), REWARD_AMOUNT - REWARD_AMOUNT / 4);
        uint256 balance = WBTC.balanceOf(user1);
        vm.startPrank(user1);
        pool.claim();
        vm.stopPrank();
        assertEq(WBTC.balanceOf(user1), balance + REWARD_AMOUNT / 4 / 2);
        assertEq(pool.farmed(user1), 0);
        assertEq(pool.farmed(user2), REWARD_AMOUNT / 4 / 2);
        assertEq(WBTC.balanceOf(address(pool)), (REWARD_AMOUNT / 4) - (REWARD_AMOUNT / 4 / 2));
        vm.warp(START + PERIOD / 2);
        assertEq(pool.farmed(user1), 0);
        assertEq(pool.farmed(user2), REWARD_AMOUNT / 4 / 2);
        vm.revertTo(snapshotId);

        // half of period passed
        vm.warp(START + PERIOD / 2);
        assertEq(pool.farmed(user1), REWARD_AMOUNT / 2 / 2);
        assertEq(pool.farmed(user2), REWARD_AMOUNT / 2 / 2);

        // user1 claims
        balance = WBTC.balanceOf(user1);
        vm.startPrank(user1);
        pool.claim();
        vm.stopPrank();
        assertEq(WBTC.balanceOf(user1), balance + REWARD_AMOUNT / 2 / 2);
        assertEq(pool.farmed(user1), 0);
        assertEq(pool.farmed(user2), REWARD_AMOUNT / 2 / 2);
        assertEq(WBTC.balanceOf(address(pool)), REWARD_AMOUNT * 3 / 4);

        // user3 stakes
        vm.startPrank(user3);
        WMST.approve(address(pool), STAKE_AMOUNT);
        pool.deposit(STAKE_AMOUNT);
        vm.stopPrank();
        assertEq(pool.totalSupply(), STAKE_AMOUNT * 3);
        assertEq(WMST.balanceOf(user3), 0);
        assertEq(pool.balanceOf(user3), STAKE_AMOUNT);
        assertEq(pool.farmed(user1), 0);
        assertEq(pool.farmed(user2), REWARD_AMOUNT / 2 / 2);
        assertEq(pool.farmed(user3), 0);

        //user2 exits
        balance = WMST.balanceOf(user2);
        vm.startPrank(user2);
        pool.exit();
        vm.stopPrank();
        assertEq(WMST.balanceOf(user2), balance + STAKE_AMOUNT);
        assertEq(pool.totalSupply(), STAKE_AMOUNT * 2);
        assertEq(pool.balanceOf(user2), 0);
        assertEq(pool.farmed(user2), 0);
        assertEq(WBTC.balanceOf(user2), REWARD_AMOUNT / 2 / 2);
        assertEq(WBTC.balanceOf(address(pool)), (REWARD_AMOUNT * 3 / 4) - (REWARD_AMOUNT / 2 / 2));

        //period finished
        vm.warp(START + PERIOD);
        assertEq(pool.farmed(user1), REWARD_AMOUNT / 2 / 2);
        assertEq(pool.farmed(user2), 0);
        assertEq(pool.farmed(user3), REWARD_AMOUNT / 2 / 2);

        //user1 exits
        balance = WMST.balanceOf(user1);
        vm.startPrank(user1);
        pool.exit();
        vm.stopPrank();
        assertEq(WMST.balanceOf(user1), balance + STAKE_AMOUNT);
        assertEq(pool.totalSupply(), STAKE_AMOUNT);
        assertEq(pool.balanceOf(user1), 0);
        assertEq(pool.farmed(user1), 0);

        //user3 exits
        balance = WMST.balanceOf(user3);
        vm.startPrank(user3);
        pool.exit();
        vm.stopPrank();
        assertEq(WMST.balanceOf(user3), balance + STAKE_AMOUNT);
        assertEq(pool.totalSupply(), 0);
        assertEq(pool.balanceOf(user3), 0);
        assertEq(pool.farmed(user3), 0);
        assertEq(WBTC.balanceOf(user3), REWARD_AMOUNT / 2 / 2);

        //post-period
        vm.warp(START + PERIOD + 1 days);
        assertEq(pool.farmed(user1), 0);
        assertEq(pool.farmed(user2), 0);
        assertEq(pool.farmed(user3), 0);
        assertEq(pool.totalSupply(), 0);
        assertEq(WBTC.balanceOf(address(pool)), 0);
        assertEq(WMST.balanceOf(address(pool)), 0);
    }
}
