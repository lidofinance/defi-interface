// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MorphoAdapter} from "src/adapters/Morpho.sol";
import {MockMetaMorpho} from "test/mocks/MockMetaMorpho.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {TestConfig} from "test/utils/TestConfig.sol";

contract MorphoAdapterTestBase is TestConfig {
    using Math for uint256;

    MorphoAdapter public vault;
    MockMetaMorpho public morpho;
    MockERC20 public usdc;
    uint8 internal assetDecimals;

    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_BALANCE = 1_000_000e6;
    uint16 public constant REWARD_FEE = 500;
    uint8 public constant OFFSET = 6;

    event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdrawn(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public virtual {
        assetDecimals = _assetDecimals();
        usdc = new MockERC20("USD Coin", "USDC", assetDecimals);
        morpho = new MockMetaMorpho(IERC20(address(usdc)), "Mock Morpho USDC", "mUSDC", OFFSET);

        vault = new MorphoAdapter(
            address(usdc), address(morpho), treasury, REWARD_FEE, OFFSET, "Morpho USDC Vault", "mvUSDC"
        );

        usdc.mint(alice, INITIAL_BALANCE);
        usdc.mint(bob, INITIAL_BALANCE);

        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _dealAndApprove(address user, uint256 amount) internal {
        usdc.mint(user, amount);
        vm.prank(user);
        usdc.approve(address(vault), amount);
    }
}
