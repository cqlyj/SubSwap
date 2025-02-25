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
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {UniversalRouter} from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {WrappedSubscription} from "./WrappedSubscription.sol";
// For now this import is commented out because Uniswap team needs to fix some issues for this to work
// import {IV4Router} from "v4-periphery/src/interfaces/IV4Router.sol";

// @update this Interface might not be correct
import {IV4Router} from "./interfaces/IV4Router.sol";

contract SubscriptionMarketplace {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

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
    UniversalRouter private immutable i_router;
    int24 private constant TICK_SPACING = 60;
    uint256 private constant DEADLINE_INTERVAL = 60;

    /*//////////////////////////////////////////////////////////////
                                 STRUCT
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error SubscriptionMarketplace__FailedToCreatePool();
    error SubscriptionMarketplace__InvalidAmount();
    error SubscriptionMarketplace__LessThanMinimumAmountOut();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event PoolCreated(PoolId indexed poolId);
    event PositionMinted(PoolId indexed poolId, uint256 tokenId);
    event SubscriptionPurchased();
    event SubscriptionSold();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _poolManager,
        address _usdc,
        address _defaultHooks,
        address _positionManager,
        address _permit2,
        address _router
    ) {
        i_poolManager = IPoolManager(_poolManager);
        i_usdc = IERC20(_usdc);
        i_defaultHooks = IHooks(_defaultHooks);
        i_positionManager = PositionManager(payable(_positionManager));
        i_permit2 = IAllowanceTransfer(_permit2);
        i_router = UniversalRouter(payable(_router));
    }

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function generateCreatePoolParams(
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
    ) external view returns (bytes[] memory) {
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

        // The following two steps should be done after get the params

        // 8. Approve the tokens
        // PositionManager uses Permit2 for token transfers

        // approve permit2 as a spender
        // _tokenApprovals(
        //     pool.currency0,
        //     i_usdc,
        //     pool.currency1,
        //     IERC20(wrappedSubscription)
        // );

        // function _tokenApprovals(
        //     Currency currency0,
        //     IERC20 token0,
        //     Currency currency1,
        //     IERC20 token1
        // ) public {
        //     if (!currency0.isAddressZero()) {
        //         token0.approve(address(i_permit2), type(uint256).max);
        //         i_permit2.approve(
        //             address(token0),
        //             address(i_positionManager),
        //             type(uint160).max,
        //             type(uint48).max
        //         );
        //     }
        //     if (!currency1.isAddressZero()) {
        //         token1.approve(address(i_permit2), type(uint256).max);
        //         i_permit2.approve(
        //             address(token1),
        //             address(i_positionManager),
        //             type(uint160).max,
        //             type(uint48).max
        //         );
        //     }
        // }

        // 9. Execute the multicall
        // This is the real command that creates the pool

        // try PositionManager(i_positionManager).multicall(params) {
        //     emit PoolCreated(pool.toId());
        // } catch {
        //     revert SubscriptionMarketplace__FailedToCreatePool();
        // }
        return params;
    }

    function generateMintPositionParams(
        // Pool parameters
        PoolKey calldata poolKey,
        // Position parameters
        int24 tickLower, // the lower tick boundary of the position
        int24 tickUpper, // the upper tick boundary of the position
        uint256 liquidity, // the amount of liquidity units to mint
        uint256 amount0Max, // the maximum amount of currency0 msg.sender is willing to pay
        uint256 amount1Max, // the maximum amount of currency1 msg.sender is willing to pay
        address recipient, // the address that will receive the liquidity position (ERC-721)
        bytes calldata hookData // encoded tokenId
    )
        external
        returns (
            bytes memory params,
            uint256 deadline,
            uint256 valueToPass,
            uint256 tokenId
        )
    {
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

        deadline = block.timestamp + DEADLINE_INTERVAL;
        valueToPass = poolKey.currency0.isAddressZero() ? amount0Max : 0;

        tokenId = i_positionManager.nextTokenId();

        // i_positionManager.modifyLiquidities{value: valueToPass}(
        //     abi.encode(actions, mintParams),
        //     deadline
        // );

        emit PositionMinted(poolKey.toId(), tokenId);
        return (
            abi.encode(actions, mintParams),
            deadline,
            valueToPass,
            tokenId
        );
    }

    /// @notice Increases liquidity in an existing position
    /// @param tokenId The ID of the position
    /// @param liquidityIncrease Amount of liquidity to add
    /// @param amount0Max Maximum amount of token0 to spend
    /// @param amount1Max Maximum amount of token1 to spend
    /// @param useFeesAsLiquidity Whether to use accumulated fees
    function generateIncreaseLiquidityParams(
        address wrappedSubscription,
        uint256 tokenId,
        uint128 liquidityIncrease,
        uint256 amount0Max,
        uint256 amount1Max,
        bool useFeesAsLiquidity
    ) external view returns (bytes memory increaseParams, uint256 deadline) {
        // Define the sequence of operations:
        // If using fees: Handle potential fee conversion
        // If not: Standard liquidity addition
        bytes memory actions;
        if (useFeesAsLiquidity) {
            actions = abi.encodePacked(
                uint8(Actions.INCREASE_LIQUIDITY), // Add liquidity
                uint8(Actions.CLOSE_CURRENCY), // Handle token0 (might need to pay or receive)
                uint8(Actions.CLOSE_CURRENCY) // Handle token1 (might need to pay or receive)
            );
        } else {
            actions = abi.encodePacked(
                uint8(Actions.INCREASE_LIQUIDITY), // Add liquidity
                uint8(Actions.SETTLE_PAIR) // Provide tokens
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
        }

        if (useFeesAsLiquidity) {
            // Using CLOSE_CURRENCY for automatic handling of each token
            params[1] = abi.encode(currency0); // Handle token0
            params[2] = abi.encode(currency1); // Handle token1
        } else {
            // Standard SETTLE_PAIR for providing tokens
            params[1] = abi.encode(currency0, currency1);
        }

        // Execute the increase
        // i_positionManager.modifyLiquidities(
        //     abi.encode(actions, params),
        //     block.timestamp + DEADLINE_INTERVAL
        // );

        return (
            abi.encode(actions, params),
            block.timestamp + DEADLINE_INTERVAL
        );
    }

    /// @notice Removes liquidity from a position
    /// @param tokenId The ID of the position
    /// @param liquidityDecrease Amount of liquidity to remove
    /// @param amount0Min Minimum amount of token0 to receive
    /// @param amount1Min Minimum amount of token1 to receive
    /// @param recipient Address to receive the tokens
    function generateDecreaseLiquidityParams(
        address wrappedSubscription,
        uint256 tokenId,
        uint128 liquidityDecrease,
        uint256 amount0Min,
        uint256 amount1Min,
        address recipient
    ) external view returns (bytes memory decreaseParams, uint256 deadline) {
        // When decreasing liquidity, you’ll receive tokens, so it's most common to receive a pair of tokens:
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY),
            uint8(Actions.TAKE_PAIR)
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
        }

        // Parameters for TAKE_PAIR
        params[1] = abi.encode(currency0, currency1, recipient);

        // Execute the decrease
        // i_positionManager.modifyLiquidities(
        //     abi.encode(actions, params),
        //     block.timestamp + DEADLINE_INTERVAL
        // );

        return (
            abi.encode(actions, params),
            block.timestamp + DEADLINE_INTERVAL
        );
    }

    // In v4’s Position Manager, there isn’t a dedicated COLLECT command.
    // Instead, fees are collected by using DECREASE_LIQUIDITY with zero liquidity.
    // This pattern leverages the fact that fees are automatically credited during liquidity operations.

    /// @notice Collects accumulated fees from a position
    /// @param tokenId The ID of the position to collect fees from
    /// @param recipient Address that will receive the fees
    function generateCollectFeesParams(
        address wrappedSubscription,
        uint256 tokenId,
        address recipient
    ) external view returns (bytes memory collectFeesParams, uint256 deadline) {
        // Define the sequence of operations
        bytes memory actions = abi.encodePacked(
            uint8(Actions.DECREASE_LIQUIDITY), // Remove liquidity
            uint8(Actions.TAKE_PAIR) // Receive both tokens
        );

        // Prepare parameters array
        bytes[] memory params = new bytes[](2);

        // Parameters for DECREASE_LIQUIDITY
        // All zeros since we're only collecting fees
        params[0] = abi.encode(
            tokenId, // Position to collect from
            0, // No liquidity change
            0, // No minimum for token0 (fees can't be manipulated)
            0, // No minimum for token1
            "" // No hook data needed
        );

        Currency currency0 = Currency.wrap(address(i_usdc));
        Currency currency1 = Currency.wrap(address(wrappedSubscription));
        if (currency0.toId() > currency1.toId()) {
            (currency0, currency1) = (currency1, currency0);
        }

        // Standard TAKE_PAIR for receiving all fees
        params[1] = abi.encode(currency0, currency1, recipient);

        // Execute fee collection
        // i_positionManager.modifyLiquidities(
        //     abi.encode(actions, params),
        //     block.timestamp + DEADLINE_INTERVAL
        // );

        return (
            abi.encode(actions, params),
            block.timestamp + DEADLINE_INTERVAL
        );
    }

    /// @notice Burns a position and receives all tokens
    /// @param tokenId The ID of the position to burn
    /// @param recipient Address that will receive the tokens
    /// @param amount0Min Minimum amount of token0 to receive
    /// @param amount1Min Minimum amount of token1 to receive
    function generateBurnPositionParams(
        address wrappedSubscription,
        uint256 tokenId,
        address recipient,
        uint256 amount0Min,
        uint256 amount1Min
    ) external view returns (bytes memory burnParams, uint256 deadline) {
        // Define the sequence of operations:
        // 1. BURN_POSITION - Removes the position and creates positive deltas
        // 2. TAKE_PAIR - Sends all tokens to the recipient
        bytes memory actions = abi.encodePacked(
            uint8(Actions.BURN_POSITION),
            uint8(Actions.TAKE_PAIR)
        );

        bytes[] memory params = new bytes[](2);

        // Parameters for BURN_POSITION
        params[0] = abi.encode(
            tokenId, // Position to burn
            amount0Min, // Minimum token0 to receive
            amount1Min, // Minimum token1 to receive
            "" // No hook data needed
        );

        Currency currency0 = Currency.wrap(address(i_usdc));
        Currency currency1 = Currency.wrap(address(wrappedSubscription));
        if (currency0.toId() > currency1.toId()) {
            (currency0, currency1) = (currency1, currency0);
        }

        // Parameters for TAKE_PAIR - where tokens will go
        params[1] = abi.encode(
            currency0, // First token
            currency1, // Second token
            recipient // Who receives the tokens
        );

        // Execute fee collection
        // i_positionManager.modifyLiquidities(
        //     abi.encode(actions, params),
        //     block.timestamp + DEADLINE_INTERVAL
        // );

        return (
            abi.encode(actions, params),
            block.timestamp + DEADLINE_INTERVAL
        );
    }

    function buySubscription(
        PoolKey memory poolKey,
        uint256 tokenId, // the exact tokenId of the subscription you want to buy
        uint128 maxAmountIn,
        uint128 amountOut // Actually it's always 1
    ) external {
        if (amountOut == 0) revert SubscriptionMarketplace__InvalidAmount();

        _approveTokenWithPermit2(
            address(i_usdc),
            maxAmountIn,
            type(uint48).max
        );

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions

        // Exact Input Swaps:
        // Use this swap-type when you know the exact amount of tokens you want to swap in, and you're willing to accept any amount of output tokens above your minimum.
        // This is common when you want to sell a specific amount of tokens.

        // Exact Output Swaps:
        // Use this swap-type when you need a specific amount of output tokens, and you're willing to spend up to a maximum amount of input tokens.
        // This is useful when you need to acquire a precise amount of tokens, for example, to repay a loan or meet a specific requirement.
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_OUT_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Encode tokenId in hook data
        bytes memory hookData = abi.encode(tokenId);

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: true, // true if we're swapping token0 for token1: USDC => NFT
                amountOut: amountOut,
                amountInMaximum: maxAmountIn,
                sqrtPriceLimitX96: 0, // No price limit
                hookData: hookData
            })
        );
        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(poolKey.currency0, maxAmountIn);
        params[2] = abi.encode(poolKey.currency1, amountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        // The block.timestamp deadline parameter ensures the transaction will be executed in the current block.
        i_router.execute(commands, inputs, block.timestamp);

        // @update
        // we may need to check the balance of the wrappedSubscription

        emit SubscriptionPurchased();
    }

    function sellSubscription(
        PoolKey memory poolKey,
        address wrappedSubscription,
        uint256 tokenId,
        uint128 amountIn,
        uint128 minAmountOut
    ) external returns (uint256 amountOut) {
        if (amountIn == 0) revert SubscriptionMarketplace__InvalidAmount();

        _approveTokenWithPermit2(
            address(wrappedSubscription),
            amountIn,
            type(uint48).max
        );

        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions

        // Exact Input Swaps:
        // Use this swap-type when you know the exact amount of tokens you want to swap in, and you're willing to accept any amount of output tokens above your minimum.
        // This is common when you want to sell a specific amount of tokens.

        // Exact Output Swaps:
        // Use this swap-type when you need a specific amount of output tokens, and you're willing to spend up to a maximum amount of input tokens.
        // This is useful when you need to acquire a precise amount of tokens, for example, to repay a loan or meet a specific requirement.
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Encode tokenId in hook data
        bytes memory hookData = abi.encode(tokenId);

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        // First parameter: swap configuration
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: true, // true if we're swapping token0 for token1: NFT => USDC
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0, // No price limit
                hookData: hookData
            })
        );
        // Second parameter: specify input tokens for the swap
        // encode SETTLE_ALL parameters
        params[1] = abi.encode(poolKey.currency1, amountIn);
        params[2] = abi.encode(poolKey.currency0, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        // The block.timestamp deadline parameter ensures the transaction will be
        // executed in the current block.
        i_router.execute(commands, inputs, block.timestamp);

        amountOut = IERC20(address(i_usdc)).balanceOf(address(this));
        if (amountOut < minAmountOut)
            revert SubscriptionMarketplace__LessThanMinimumAmountOut();

        emit SubscriptionSold();

        return amountOut;
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _approveTokenWithPermit2(
        address token,
        uint160 amount,
        uint48 expiration
    ) internal {
        IERC20(token).approve(address(i_permit2), type(uint256).max);
        i_permit2.approve(token, address(i_router), amount, expiration);
    }

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

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getPoolManager() external view returns (IPoolManager) {
        return i_poolManager;
    }

    function getUSDC() external view returns (IERC20) {
        return i_usdc;
    }

    function getDefaultHooks() external view returns (IHooks) {
        return i_defaultHooks;
    }

    function getPositionManager() external view returns (PositionManager) {
        return i_positionManager;
    }

    function getPermit2() external view returns (IAllowanceTransfer) {
        return i_permit2;
    }

    function getRouter() external view returns (UniversalRouter) {
        return i_router;
    }

    function getTickSpacing() external pure returns (int24) {
        return TICK_SPACING;
    }

    function getDeadlineInterval() external pure returns (uint256) {
        return DEADLINE_INTERVAL;
    }

    function getPoolId(PoolKey memory poolKey) external pure returns (PoolId) {
        return poolKey.toId();
    }

    function getPoolState(
        PoolKey calldata key
    )
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint24 protocolFee,
            uint24 lpFee
        )
    {
        return i_poolManager.getSlot0(key.toId());
    }

    function getPoolLiquidity(
        PoolKey calldata key
    ) external view returns (uint128 liquidity) {
        return i_poolManager.getLiquidity(key.toId());
    }

    function getPositionInfo(
        PoolKey calldata key,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        bytes32 salt
    )
        external
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128
        )
    {
        return
            i_poolManager.getPositionInfo(
                key.toId(),
                owner,
                tickLower,
                tickUpper,
                bytes32(salt)
            );
    }

    function getPoolKey(
        address wrappedSubscription,
        uint24 swapFee,
        IHooks hooks
    ) external view returns (PoolKey memory) {
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
}
