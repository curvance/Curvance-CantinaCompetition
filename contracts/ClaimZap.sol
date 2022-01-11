// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./interfaces/MathUtil.sol";
import "./interfaces/ILockedCvx.sol";
import "./interfaces/IClaimZap.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

//Claim zap to bundle various reward claims
//v2:
// - change exchange to use curve pool
// - add getReward(address,token) type
// - add option to lock cvx
// - add option use all funds in wallet

contract ClaimZap {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public constant crv = address(0xD533a949740bb3306d119CC777fa900bA034cd52);
    address public constant cvx = address(0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B);
    address public constant cvxCrv = address(0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7);
    address public constant crvDeposit = address(0x8014595F2AB54cD7c604B00E9fb932176fDc86Ae);
    address public constant cvxCrvRewards = address(0x3Fe65692bfCD0e6CF84cB1E7d24108E434A7587e);
    address public constant cvxRewards = address(0xCF50b810E57Ac33B91dCF525C6ddd9881B139332);

    address public constant exchange = address(0x9D0464996170c6B9e75eED71c68B99dDEDf279e8); //curve

    address public constant locker = address(0xD18140b4B819b895A3dba5442F959fA44994AF50);

    address public immutable owner;

    struct ClaimRewardsParams {
        uint256 depositCrvMaxAmount;
        uint256 minAmountOut;
        uint256 depositCvxMaxAmount;
        uint256 spendCvxAmount;
        uint256 options;
    }

    enum Options {
        ClaimCvx, //1
        ClaimCvxAndStake, //2
        ClaimCvxCrv, //4
        ClaimLockedCvx, //8
        ClaimLockedCvxStake, //16
        LockCrvDeposit, //32
        UseAllWalletFunds, //64
        LockCvx //128
    }

    constructor() {
        owner = msg.sender;
    }

    function getName() external pure returns (string memory) {
        return "ClaimZap V2.0";
    }

    function setApprovals() external {
        require(msg.sender == owner, "!auth");
        IERC20(crv).safeApprove(crvDeposit, 0);
        IERC20(crv).safeApprove(crvDeposit, type(uint128).max);
        IERC20(crv).safeApprove(exchange, 0);
        IERC20(crv).safeApprove(exchange, type(uint128).max);

        IERC20(cvx).safeApprove(cvxRewards, 0);
        IERC20(cvx).safeApprove(cvxRewards, type(uint128).max);

        IERC20(cvxCrv).safeApprove(cvxCrvRewards, 0);
        IERC20(cvxCrv).safeApprove(cvxCrvRewards, type(uint128).max);

        IERC20(cvx).safeApprove(locker, 0);
        IERC20(cvx).safeApprove(locker, type(uint128).max);
    }

    function CheckOption(uint256 _mask, uint256 _flag) internal pure returns (bool) {
        return (_mask & (1 << _flag)) != 0;
    }

    function claimRewards(
        address[] calldata rewardContracts,
        address[] calldata extraRewardContracts,
        address[] calldata tokenRewardContracts,
        address[] calldata tokenRewardTokens,
        ClaimRewardsParams memory params
    ) external {
        uint256 crvBalance = IERC20(crv).balanceOf(msg.sender);
        uint256 cvxBalance = IERC20(cvx).balanceOf(msg.sender);

        //claim from main curve LP pools
        for (uint256 i = 0; i < rewardContracts.length; i++) {
            IBasicRewards(rewardContracts[i]).getReward(msg.sender, true);
        }
        //claim from extra rewards
        for (uint256 i = 0; i < extraRewardContracts.length; i++) {
            IBasicRewards(extraRewardContracts[i]).getReward(msg.sender);
        }
        //claim from multi reward token contract
        for (uint256 i = 0; i < tokenRewardContracts.length; i++) {
            IBasicRewards(tokenRewardContracts[i]).getReward(msg.sender, tokenRewardTokens[i]);
        }

        //claim others/deposit/lock/stake
        _claimExtras(crvBalance, cvxBalance, params);
    }

    function _claimExtras(
        uint256 removeCrvBalance,
        uint256 removeCvxBalance,
        ClaimRewardsParams memory params
    ) internal {
        //claim (and stake) from cvx rewards
        if (CheckOption(params.options, uint256(Options.ClaimCvxAndStake))) {
            ICvxRewards(cvxRewards).getReward(msg.sender, true, true);
        } else if (CheckOption(params.options, uint256(Options.ClaimCvx))) {
            ICvxRewards(cvxRewards).getReward(msg.sender, true, false);
        }

        //claim from cvxCrv rewards
        if (CheckOption(params.options, uint256(Options.ClaimCvxCrv))) {
            IBasicRewards(cvxCrvRewards).getReward(msg.sender, true);
        }

        //claim from locker
        if (CheckOption(params.options, uint256(Options.ClaimLockedCvx))) {
            ILockedCvx(locker).getReward(msg.sender, CheckOption(params.options, uint256(Options.ClaimLockedCvxStake)));
        }

        //reset remove balances if we want to also stake/lock funds already in our wallet
        if (CheckOption(params.options, uint256(Options.UseAllWalletFunds))) {
            removeCrvBalance = 0;
            removeCvxBalance = 0;
        }

        //lock upto given amount of crv and stake
        if (params.depositCrvMaxAmount > 0) {
            uint256 crvBalance = IERC20(crv).balanceOf(msg.sender).sub(removeCrvBalance);
            crvBalance = MathUtil.min(crvBalance, params.depositCrvMaxAmount);
            if (crvBalance > 0) {
                //pull crv
                IERC20(crv).safeTransferFrom(msg.sender, address(this), crvBalance);
                if (params.minAmountOut > 0) {
                    //swap
                    ISwapExchange(exchange).exchange(0, 1, crvBalance, params.minAmountOut);
                } else {
                    //deposit
                    ICvxCrvDeposit(crvDeposit).deposit(
                        crvBalance,
                        CheckOption(params.options, uint256(Options.LockCrvDeposit))
                    );
                }
                //get cvxcrv amount
                uint256 cvxCrvBalance = IERC20(cvxCrv).balanceOf(address(this));
                //stake for msg.sender
                IBasicRewards(cvxCrvRewards).stakeFor(msg.sender, cvxCrvBalance);
            }
        }

        //stake up to given amount of cvx
        if (params.depositCvxMaxAmount > 0) {
            uint256 cvxBalance = IERC20(cvx).balanceOf(msg.sender).sub(removeCvxBalance);
            cvxBalance = MathUtil.min(cvxBalance, params.depositCvxMaxAmount);
            if (cvxBalance > 0) {
                //pull cvx
                IERC20(cvx).safeTransferFrom(msg.sender, address(this), cvxBalance);
                if (CheckOption(params.options, uint256(Options.LockCvx))) {
                    ILockedCvx(locker).lock(msg.sender, cvxBalance, params.spendCvxAmount);
                } else {
                    //stake for msg.sender
                    IBasicRewards(cvxRewards).stakeFor(msg.sender, cvxBalance);
                }
            }
        }
    }
}
