// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";
import "../src/InfraStaking.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InfraStakingTest is Test {
    InfraStaking infraStaking;

    address admin = makeAddr("admin");
    address user = makeAddr("user");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address other = makeAddr("other");

    address impersonatedUser = address(0xeefbd314141BF7933Be47E44C1dC1437e58604Cb);

    function setUp() public {
        // Fork Avalanche mainnet
        vm.createSelectFork(vm.rpcUrl("avalanche"));

        vm.makePersistent(user);
        vm.makePersistent(user2);
        vm.makePersistent(user3);
        vm.makePersistent(other);

        vm.makePersistent(admin);

        vm.makePersistent(impersonatedUser);

        infraStaking = new InfraStaking(
            address(0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE), address(0xE3C983013B8c5830D866F550a28fD7Ed4393d5B7)
        );
    }

    function test_stake() external {
        vm.deal(user, 100 ether);

        changePrank(user);
        infraStaking.stake{value: 100 ether}();

        (uint256 _sAvaxBalance, uint256 _defaultCollateralStakedAvax) = infraStaking.userBalances(address(user));

        (, uint256 sAvaxBalance, uint256 defaultCollateralStakedAvax,,,) = infraStaking.userInfo(user);

        assertEq(_sAvaxBalance, sAvaxBalance);
        assertEq(_defaultCollateralStakedAvax, defaultCollateralStakedAvax);
    }

    function test_requestUnlock() external {
        vm.deal(user, 100 ether);

        changePrank(user);
        infraStaking.stake{value: 100 ether}();

        vm.warp(block.timestamp + 52 weeks);
        changePrank(user);
        infraStaking.requestUnlock();

        (uint256 startedAt, uint256 shareAmount) = infraStaking.userUnlockRequests(0);

        console.log("startedAt: ", startedAt);
        console.log("shareAmount: ", shareAmount);

        vm.warp(block.timestamp + 16 days);

        infraStaking.claimUnstakes();

        console.log("User balance: ", user.balance);

        (uint256 _sAvaxBalance, uint256 _defaultCollateralStakedAvax) = infraStaking.userBalances(address(user));

        console.log("user sAvax balance: ", _sAvaxBalance);
        console.log("user defaultCollateralStakedAvax balance: ", _defaultCollateralStakedAvax);
    }

    function test_stake_multiple_users() external {
        vm.deal(user, 50 ether);
        vm.deal(user2, 50 ether);
        vm.deal(user3, 50 ether);

        // User 1 stakes
        changePrank(user);
        infraStaking.stake{value: 50 ether}();
        (uint256 _sAvaxBalance, uint256 _defaultCollateralStakedAvax) = infraStaking.userBalances(address(user));
        assertGt(_sAvaxBalance, 0);
        assertGt(_defaultCollateralStakedAvax, 0);

        // User 2 stakes
        changePrank(user2);
        infraStaking.stake{value: 50 ether}();
        (uint256 _sAvaxBalance2, uint256 _defaultCollateralStakedAvax2) = infraStaking.userBalances(address(user2));
        assertGt(_sAvaxBalance2, 0);
        assertGt(_defaultCollateralStakedAvax2, 0);

        // User 3 stakes
        changePrank(user3);
        infraStaking.stake{value: 50 ether}();
        (uint256 _sAvaxBalance3, uint256 _defaultCollateralStakedAvax3) = infraStaking.userBalances(address(user3));
        assertGt(_sAvaxBalance3, 0);
        assertGt(_defaultCollateralStakedAvax3, 0);
    }

    function test_requestUnlock_before_stake() external {
        changePrank(user);
        // vm.expectRevert("Invalid unlock amount"); // Should revert as user has no balance
        vm.expectRevert();
        infraStaking.requestUnlock();
    }

    function test_claimUnstakes_before_unlock_period() external {
        vm.deal(user, 100 ether);

        changePrank(user);
        infraStaking.stake{value: 100 ether}();
        infraStaking.requestUnlock();

        // Try to claim before unlock period
        vm.expectRevert(InfraStaking.UnlockPeriodNotOver.selector);
        infraStaking.claimUnstakes();
    }

    function test_claimUnstakes_without_request() external {
        vm.deal(user, 100 ether);

        changePrank(user);
        infraStaking.stake{value: 100 ether}();

        vm.expectRevert(InfraStaking.NoUnstakeRequest.selector);
        infraStaking.claimUnstakes();
    }

    function test_full_unstake_flow() external {
        vm.deal(user, 100 ether);

        // Stake
        changePrank(user);
        infraStaking.stake{value: 100 ether}();
        (uint256 _sAvaxBalance, uint256 _defaultCollateralStakedAvax) = infraStaking.userBalances(address(user));
        assertGt(_sAvaxBalance, 0);
        assertGt(_defaultCollateralStakedAvax, 0);

        // Request unlock
        infraStaking.requestUnlock();
        (,,, uint256 pendingUnstake,,) = infraStaking.userInfo(user);
        assertEq(pendingUnstake, _sAvaxBalance);

        // Wait for unlock period
        vm.warp(block.timestamp + 16 days);

        // Claim unstakes
        uint256 balanceBeforeClaim = user.balance;
        infraStaking.claimUnstakes();
        uint256 balanceAfterClaim = user.balance;

        // Verify user received funds
        assertGt(balanceAfterClaim, balanceBeforeClaim);

        // Verify user data is cleared
        (
            uint256 stakedAmount,
            uint256 sAvaxBalance,
            uint256 defaultCollateralStakedAvax,
            uint256 pendingUnstakeAmount,
            uint256 nextClaimtime,
            uint256 unlockRequestIndex
        ) = infraStaking.userInfo(user);
        assertEq(stakedAmount, 0);
        assertEq(sAvaxBalance, 0);
        assertEq(defaultCollateralStakedAvax, 0);
        assertEq(pendingUnstakeAmount, 0);
        assertEq(nextClaimtime, 0);
        assertEq(unlockRequestIndex, 0);
    }

    function test_multiple_stake_unstake_cycles() external {
        vm.deal(user, 200 ether);

        // First stake cycle
        changePrank(user);
        infraStaking.stake{value: 100 ether}();

        // First unstake cycle
        infraStaking.requestUnlock();
        vm.warp(block.timestamp + 16 days);
        uint256 balanceBeforeFirstClaim = user.balance;
        infraStaking.claimUnstakes();
        uint256 balanceAfterFirstClaim = user.balance;
        assertGt(balanceAfterFirstClaim, balanceBeforeFirstClaim);

        // Second stake cycle
        infraStaking.stake{value: 100 ether}();

        // Second unstake cycle
        infraStaking.requestUnlock();
        vm.warp(block.timestamp + 16 days);
        uint256 balanceBeforeSecondClaim = user.balance;
        infraStaking.claimUnstakes();
        uint256 balanceAfterSecondClaim = user.balance;
        assertGt(balanceAfterSecondClaim, balanceBeforeSecondClaim);
    }

    function test_multiple_users_unstake_and_claim_after_cool_down_period() external {
        vm.deal(user, 150 ether);
        vm.deal(user2, 150 ether);
        vm.deal(user3, 150 ether);

        changePrank(user);
        infraStaking.stake{value: 100 ether}();
        infraStaking.stake{value: 50 ether}();

        changePrank(user2);
        infraStaking.stake{value: 100 ether}();
        infraStaking.stake{value: 50 ether}();

        changePrank(user3);
        infraStaking.stake{value: 100 ether}();
        infraStaking.stake{value: 50 ether}();

        // unstake
        changePrank(user);
        infraStaking.requestUnlock();
        vm.warp(block.timestamp + 16 days);
        infraStaking.claimUnstakes();

        // unstake user2
        changePrank(user2);
        infraStaking.requestUnlock();
        vm.warp(block.timestamp + 16 days);
        infraStaking.claimUnstakes();

        // unstake user3
        changePrank(user3);
        infraStaking.requestUnlock();
        vm.warp(block.timestamp + 16 days);
        infraStaking.claimUnstakes();

        // validate that the user received the correct amount of default collateral
        (uint256 _sAvaxBalance, uint256 _defaultCollateralStakedAvax) = infraStaking.userBalances(address(user));
        (uint256 _sAvaxBalance2, uint256 _defaultCollateralStakedAvax2) = infraStaking.userBalances(address(user2));
        (uint256 _sAvaxBalance3, uint256 _defaultCollateralStakedAvax3) = infraStaking.userBalances(address(user3));

        assertEq(_sAvaxBalance, 0);
        assertEq(_defaultCollateralStakedAvax, 0);

        assertEq(_sAvaxBalance2, 0);
        assertEq(_defaultCollateralStakedAvax2, 0);

        assertEq(_sAvaxBalance3, 0);
        assertEq(_defaultCollateralStakedAvax3, 0);

        // check user balance
        assertGe(user.balance, 149 ether);
        assertGe(user2.balance, 149 ether);
        assertGe(user3.balance, 149 ether);

        // check contract balance
        assertEq(address(infraStaking).balance, 0);
        assertEq(IERC20(address(0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE)).balanceOf(address(infraStaking)), 0);
        assertEq(IERC20(address(0xE3C983013B8c5830D866F550a28fD7Ed4393d5B7)).balanceOf(address(infraStaking)), 0);
    }
}
