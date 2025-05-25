// SPDX-License-Identifier: MIT
pragma solidity =0.8.27 ^0.8.20;

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.1.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// src/InfraStaking.sol

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

