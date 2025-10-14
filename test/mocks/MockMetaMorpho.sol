// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockMetaMorpho is ERC4626 {
    using SafeERC20 for IERC20;

    uint256 public yieldRate = 10;

    uint256 public liquidityCap = type(uint256).max;

    uint256 public lastYieldAccrual;
    uint256 public autoAccrualInterval = 0;

    event YieldAccrued(uint256 amount);
    event LiquidityConstrained(uint256 requested, uint256 available);

    constructor(
        IERC20 asset_,
        string memory name_,
        string memory symbol_
    ) ERC4626(asset_) ERC20(name_, symbol_) {
        lastYieldAccrual = block.timestamp;
    }

    function accrueYield() public {
        uint256 currentAssets = totalAssets();
        if (currentAssets == 0) return;

        uint256 yieldAmount = (currentAssets * yieldRate) / 10000;

        if (yieldAmount > 0) {
            emit YieldAccrued(yieldAmount);
        }

        lastYieldAccrual = block.timestamp;
    }

    function _maybeAccrueYield() internal {
        if (
            autoAccrualInterval > 0 &&
            block.timestamp >= lastYieldAccrual + autoAccrualInterval
        ) {
            accrueYield();
        }
    }

    function setYieldRate(uint256 rate) external {
        yieldRate = rate;
    }

    function setLiquidityCap(uint256 cap) external {
        liquidityCap = cap;
    }

    function setAutoAccrualInterval(uint256 interval) external {
        autoAccrualInterval = interval;
    }

    function getMockState()
        external
        view
        returns (
            uint256 totalAssets_,
            uint256 totalSupply_,
            uint256 sharePrice_,
            uint256 yieldRate_,
            uint256 liquidityCap_
        )
    {
        totalAssets_ = totalAssets();
        totalSupply_ = totalSupply();
        sharePrice_ = totalSupply_ > 0
            ? (totalAssets_ * 1e18) / totalSupply_
            : 1e18;
        yieldRate_ = yieldRate;
        liquidityCap_ = liquidityCap;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 baseMax = super.maxWithdraw(owner);
        return baseMax > liquidityCap ? liquidityCap : baseMax;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 maxAssets = maxWithdraw(owner);
        return convertToShares(maxAssets);
    }
}
