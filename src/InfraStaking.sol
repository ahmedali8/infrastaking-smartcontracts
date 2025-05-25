// SPDX-License-Identifier: MIT

pragma solidity 0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBenqiLiquidStaking {
    function submit() external payable returns (uint256);
    function redeem(uint256 unlockIndex) external;
    function requestUnlock(uint256 _shareAmount) external;
    function userUnlockRequests(address _user, uint256 _index) external view returns (uint256, uint256);
    function cooldownPeriod() external view returns (uint256);
}

interface IDefaultCollateral {
    /**
     * @notice Deposit a given amount of the underlying asset, and mint the collateral to a particular recipient.
     * @param recipient address of the collateral's recipient
     * @param amount amount of the underlying asset
     * @return amount of the collateral minted
     */
    function deposit(address recipient, uint256 amount) external returns (uint256);

    /**
     * @notice Withdraw a given amount of the underlying asset, and transfer it to a particular recipient.
     * @param recipient address of the underlying asset's recipient
     * @param amount amount of the underlying asset
     */
    function withdraw(address recipient, uint256 amount) external;
}

contract InfraStaking {
    event Staked(address indexed user, uint256 amount, uint256 sAvaxBalance, uint256 defaultCollateralStakedAvax);
    event UnstakeRequested(address indexed user, uint256 amountToUnstake);
    event Unstaked(address indexed user, uint256 totalClaimed);

    error InsufficientBalance();
    error UnlockPeriodNotOver();
    error TransferFailed();
    error NoUnstakeRequest();

    struct User {
        uint256 stakedAmount;
        uint256 sAvaxBalance;
        uint256 defaultCollateralStakedAvax;
        uint256 pendingUnstakeAmount;
        uint256 nextClaimtime;
        uint256 unlockRequestIndex;
    }

    IBenqiLiquidStaking public immutable benqiLiquidStaking;
    IDefaultCollateral public immutable defaultCollateral;
    mapping(address user => User userInfo) public userInfo;

    constructor(address _benqiLiquidStaking, address _defaultCollateral) {
        benqiLiquidStaking = IBenqiLiquidStaking(_benqiLiquidStaking);
        defaultCollateral = IDefaultCollateral(_defaultCollateral);
    }

    function stake() external payable {
        User storage user = userInfo[msg.sender];

        uint256 stakeAmount = msg.value;
        user.stakedAmount += stakeAmount;
        uint256 shareAmount = benqiLiquidStaking.submit{value: stakeAmount}();
        user.sAvaxBalance += shareAmount;

        IERC20(address(benqiLiquidStaking)).approve(address(defaultCollateral), shareAmount);
        uint256 defaultCollateralStakedAvax = defaultCollateral.deposit(address(this), shareAmount);
        user.defaultCollateralStakedAvax += defaultCollateralStakedAvax;

        emit Staked(msg.sender, stakeAmount, shareAmount, defaultCollateralStakedAvax);
    }

    function requestUnlock() external {
        User storage user = userInfo[msg.sender];

        uint256 amount = user.defaultCollateralStakedAvax;

        defaultCollateral.withdraw(address(this), amount);
        unchecked {
            user.defaultCollateralStakedAvax -= amount;
        }

        uint256 amountToUnstake = user.sAvaxBalance;

        user.pendingUnstakeAmount += amountToUnstake;
        user.nextClaimtime = block.timestamp + benqiLiquidStaking.cooldownPeriod();
        benqiLiquidStaking.requestUnlock(amountToUnstake);
        user.unlockRequestIndex++;

        emit UnstakeRequested(msg.sender, amountToUnstake);
    }

    function claimUnstakes() external {
        User storage user = userInfo[msg.sender];

        if (user.nextClaimtime == 0) {
            revert NoUnstakeRequest();
        }

        if (block.timestamp < user.nextClaimtime) {
            revert UnlockPeriodNotOver();
        }

        uint256 unlockRequestIndex;

        unchecked {
            unlockRequestIndex = user.unlockRequestIndex - 1;
        }

        benqiLiquidStaking.redeem(unlockRequestIndex);
        uint256 nativeBalance = address(this).balance;

        if (nativeBalance > 0) {
            (bool success,) = msg.sender.call{value: nativeBalance}("");
            if (success) {
                emit Unstaked(msg.sender, nativeBalance);
                delete userInfo[msg.sender];
            } else {
                revert TransferFailed();
            }
        }
    }

    function userBalances(address _user) external view returns (uint256, uint256) {
        return (userInfo[_user].sAvaxBalance, userInfo[_user].defaultCollateralStakedAvax);
    }

    function userUnlockRequests(uint256 _index) external view returns (uint256, uint256) {
        return benqiLiquidStaking.userUnlockRequests(address(this), _index);
    }

    receive() external payable {}
    fallback() external payable {}
}
