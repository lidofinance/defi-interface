// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";

abstract contract TestConfig is Test {
    error AssetDecimalsTooLarge(uint256 provided);

    uint8 internal _assetDecimalsCache;
    bool internal _assetDecimalsInitialized;

    function _assetDecimals() internal returns (uint8) {
        if (!_assetDecimalsInitialized) {
            uint256 overrideValue = vm.envOr("ASSET_DECIMALS", uint256(6));
            if (overrideValue > type(uint8).max) revert AssetDecimalsTooLarge(overrideValue);
            _assetDecimalsCache = uint8(overrideValue);
            _assetDecimalsInitialized = true;
        }
        return _assetDecimalsCache;
    }
}
