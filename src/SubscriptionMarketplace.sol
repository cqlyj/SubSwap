// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolKey, PoolIdLibrary} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

// import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

contract SubscriptionMarketplace {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    // using StateLibrary for IPoolManager;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IPoolManager private immutable i_poolManager;
    IERC20 private immutable i_usdc;
    IHooks private immutable i_defaultHooks; // SubscriptionPricingHook
    PositionManager private immutable i_positionManager;
    // Deployed Permit2 bytecode at
    // https://etherscan.io/address/0x000000000022D473030F116dDEE9F6B43aC78BA3#code
    IAllowanceTransfer private immutable i_permit2;
    int24 private constant TICK_SPACING = 60;
    uint256 private constant DEADLINE_INTERVAL = 60;

    /*//////////////////////////////////////////////////////////////
                                 STRUCT
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SubscriptionMarketplace__FailedToCreatePool();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PoolCreated(PoolId indexed poolId);
    event PositionMinted(PoolId indexed poolId, uint256 tokenId);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _poolManager,
        address _usdc,
        address _defaultHooks,
        address _positionManager,
        address _permit2
    ) {
        i_poolManager = IPoolManager(_poolManager);
        i_usdc = IERC20(_usdc);
        i_defaultHooks = IHooks(_defaultHooks);
        i_positionManager = PositionManager(payable(_positionManager));
        i_permit2 = IAllowanceTransfer(_permit2);
    }

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function createPool(
        address wrappedSubscription,
        uint24 swapFee,
        IHooks hooks,
        uint160 startingPrice,
        int24 tickLower,
        int24 tickUpper,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 amount0Max,
        uint256 amount1Max,
        bytes calldata hookData // encoded tokenId
    ) external {
        // 1. Initialize the parameters provided to multicall()

        // The first call, params[0], will encode initializePool parameters
        // The second call, params[1], will encode a mint operation for modifyLiquidities
        bytes[] memory params = new bytes[](2);

        // 2. Configure the pool

        // Currencies should be sorted, uint160(currency0) < uint160(currency1)
        // lpFee is the fee expressed in pips, i.e. 3000 = 0.30%
        // tickSpacing is the granularity of the pool. Lower values are more precise but more expensive to trade
        // hookContract is the address of the hook contract

        PoolKey memory pool = _configurePool(
            wrappedSubscription,
            swapFee,
            hooks
        );

        // 3. Encode the initializePool parameters

        // the startingPrice is expressed as sqrtPriceX96: floor(sqrt(token1 / token0) * 2^96)
        // 79228162514264337593543950336 is the starting price for a 1:1 pool
        params[0] = _initializePool(pool, startingPrice);

        // 4. Initialize the mint-liquidity parameters
        // 5. Encode the MINT_POSITION parameters
        // 6. Encode the SETTLE_PAIR parameters

        // Converts token amounts to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            token0Amount,
            token1Amount
        );

        (
            bytes memory actions,
            bytes[] memory mintParams
        ) = _mintLiquidityParams(
                pool,
                tickLower,
                tickUpper,
                liquidity,
                amount0Max,
                amount1Max,
                msg.sender,
                hookData
            );

        // 7. Encode the modifyLiquidites call

        // It ensures that the transaction fails if it's not executed within 60 seconds.
        // Used to prevent front-running or delayed execution.
        uint256 deadline = block.timestamp + DEADLINE_INTERVAL;
        params[1] = abi.encodeWithSelector(
            i_positionManager.modifyLiquidities.selector,
            abi.encode(actions, mintParams),
            deadline
        );

        // 8. Approve the tokens
        // PositionManager uses Permit2 for token transfers

        // approve permit2 as a spender
        _tokenApprovals(
            pool.currency0,
            i_usdc,
            pool.currency1,
            IERC20(wrappedSubscription)
        );

        // 9. Execute the multicall

        try PositionManager(i_positionManager).multicall(params) {
            emit PoolCreated(pool.toId());
        } catch {
            revert SubscriptionMarketplace__FailedToCreatePool();
        }
    }

    function mintPosition(
        // Pool parameters
        PoolKey calldata poolKey,
        // Position parameters
        int24 tickLower,
        int24 tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes calldata hookData // encoded tokenId
    ) external returns (uint256 tokenId) {
        (
            bytes memory actions,
            bytes[] memory mintParams
        ) = _mintLiquidityParams(
                poolKey,
                tickLower,
                tickUpper,
                liquidity,
                amount0Max,
                amount1Max,
                recipient,
                hookData
            );

        uint256 deadline = block.timestamp + DEADLINE_INTERVAL;
        uint256 valueToPass = poolKey.currency0.isAddressZero()
            ? amount0Max
            : 0;

        tokenId = i_positionManager.nextTokenId();
        i_positionManager.modifyLiquidities{value: valueToPass}(
            abi.encode(actions, mintParams),
            deadline
        );

        emit PositionMinted(poolKey.toId(), tokenId);
    }

    /// @notice Increases liquidity in an existing position
    /// @param tokenId The ID of the position
    /// @param liquidityIncrease Amount of liquidity to add
    /// @param amount0Max Maximum amount of token0 to spend
    /// @param amount1Max Maximum amount of token1 to spend
    /// @param useFeesAsLiquidity Whether to use accumulated fees
    function increaseLiquidity(
        address wrappedSubscription,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint256 amount0Max,
        uint256 amount1Max,
        bool useFeesAsLiquidity
    ) external {
        // Define the sequence of operations:
        // If using fees: Handle potential fee conversion
        // If not: Standard liquidity addition
        bytes memory actions;
        if (useFeesAsLiquidity) {
            actions = abi.encodePacked(
                Actions.INCREASE_LIQUIDITY, // Add liquidity
                Actions.CLOSE_CURRENCY, // Handle token0 (might need to pay or receive)
                Actions.CLOSE_CURRENCY // Handle token1 (might need to pay or receive)
            );
        } else {
            actions = abi.encodePacked(
                Actions.INCREASE_LIQUIDITY, // Add liquidity
                Actions.SETTLE_PAIR // Provide tokens
            );
        }

        // Number of parameters depends on our strategy
        bytes[] memory params = new bytes[](useFeesAsLiquidity ? 3 : 2);

        // Parameters for INCREASE_LIQUIDITY
        params[0] = abi.encode(
            tokenId, // Position to increase
            liquidityIncrease, // Amount to add
            amount0Max, // Maximum token0 to spend
            amount1Max, // Maximum token1 to spend
            "" // No hook data needed
        );

        Currency currency0 = Currency.wrap(address(i_usdc));
        Currency currency1 = Currency.wrap(address(wrappedSubscription));
        if (currency0.toId() > currency1.toId()) {
            (currency0, currency1) = (currency1, currency0);

            if (useFeesAsLiquidity) {
                // Using CLOSE_CURRENCY for automatic handling of each token
                params[1] = abi.encode(currency0); // Handle token0
                params[2] = abi.encode(currency1); // Handle token1
            } else {
                // Standard SETTLE_PAIR for providing tokens
                params[1] = abi.encode(currency0, currency1);
            }

            // Execute the increase
            i_positionManager.modifyLiquidities(
                abi.encode(actions, params),
                block.timestamp + DEADLINE_INTERVAL
            );
        }
    }

    /// @notice Removes liquidity from a position
    /// @param tokenId The ID of the position
    /// @param liquidityDecrease Amount of liquidity to remove
    /// @param amount0Min Minimum amount of token0 to receive
    /// @param amount1Min Minimum amount of token1 to receive
    /// @param recipient Address to receive the tokens
    function decreaseLiquidity(
        address wrappedSubscription,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) external {
        // When decreasing liquidity, you’ll receive tokens, so it's most common to receive a pair of tokens:
        bytes memory actions = abi.encodePacked(
            Actions.DECREASE_LIQUIDITY,
            Actions.TAKE_PAIR
        );

        bytes[] memory params = new bytes[](2);

        // Parameters for DECREASE_LIQUIDITY
        params[0] = abi.encode(
            tokenId, // Position to decrease
            liquidityDecrease, // Amount to remove
            amount0Min, // Minimum token0 to receive
            amount1Min, // Minimum token1 to receive
            "" // No hook data needed
        );

        Currency currency0 = Currency.wrap(address(i_usdc));
        Currency currency1 = Currency.wrap(address(wrappedSubscription));
        if (currency0.toId() > currency1.toId()) {
            (currency0, currency1) = (currency1, currency0);

            // Parameters for TAKE_PAIR
            params[1] = abi.encode(currency0, currency1, recipient);

            // Execute the decrease
            i_positionManager.modifyLiquidities(
                abi.encode(actions, params),
                block.timestamp + DEADLINE_INTERVAL
            );
        }
    }

    function collectFees() external {}

    function burnPosition() external {}

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _initializePool(
        PoolKey memory pool,
        uint160 startingPrice
    ) internal view returns (bytes memory) {
        return
            abi.encodeWithSelector(
                i_positionManager.initializePool.selector,
                pool,
                startingPrice
            );
    }

    function _configurePool(
        address wrappedSubscription,
        uint24 swapFee,
        IHooks hooks
    ) internal view returns (PoolKey memory pool) {
        Currency currency0 = Currency.wrap(address(i_usdc));
        Currency currency1 = Currency.wrap(address(wrappedSubscription));
        if (currency0.toId() > currency1.toId()) {
            (currency0, currency1) = (currency1, currency0);
        }
        if (hooks == IHooks(address(0))) {
            hooks = i_defaultHooks;
        }
        return
            PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: swapFee,
                tickSpacing: TICK_SPACING,
                hooks: hooks
            });
    }

    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes calldata hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        // The first command MINT_POSITION creates a new liquidity position
        // The second command SETTLE_PAIR indicates that tokens are to be paid by the caller, to create the position
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        // pool the same PoolKey defined above, in pool-creation
        // tickLower and tickUpper are the range of the position, must be a multiple of pool.tickSpacing
        // liquidity is the amount of liquidity units to add, see LiquidityAmounts for converting token amounts to liquidity units
        // amount0Max and amount1Max are the maximum amounts of token0 and token1 the caller is willing to transfer
        // recipient is the address that will receive the liquidity position (ERC-721)
        // hookData is the optional hook data

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            poolKey,
            _tickLower,
            _tickUpper,
            liquidity,
            amount0Max,
            amount1Max,
            // The recipient of the liquidity position is the caller, he owns the NFT
            recipient,
            hookData
        );
        // Creating a position on a pool requires the caller to transfer `currency0` and `currency1` tokens
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        return (actions, params);
    }

    function _tokenApprovals(
        Currency currency0,
        IERC20 token0,
        Currency currency1,
        IERC20 token1
    ) public {
        if (!currency0.isAddressZero()) {
            token0.approve(address(i_permit2), type(uint256).max);
            i_permit2.approve(
                address(token0),
                address(i_positionManager),
                type(uint160).max,
                type(uint48).max
            );
        }
        if (!currency1.isAddressZero()) {
            token1.approve(address(i_permit2), type(uint256).max);
            i_permit2.approve(
                address(token1),
                address(i_positionManager),
                type(uint160).max,
                type(uint48).max
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
}
