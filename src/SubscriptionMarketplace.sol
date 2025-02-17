// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolKey, PoolIdLibrary} from "v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IWrappedSubscription} from "./interfaces/IWrappedSubscription.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PositionManager} from "v4-periphery/src/PositionManager.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

contract SubscriptionMarketplace {
    using SafeERC20 for IERC20;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IPoolManager private immutable i_poolManager;
    IWrappedSubscription private immutable i_wrappedSubscription;
    IERC20 private immutable i_usdc;
    IHooks private immutable i_defaultHooks; // SubscriptionPricingHook
    PositionManager private immutable i_positionManager;
    IAllowanceTransfer private immutable i_permit2;
    int24 private constant TICK_SPACING = 60;
    int24 private constant TICK_LOWER = -600;
    int24 private constant TICK_UPPER = 600;
    uint256 private constant DEADLINE_INTERVAL = 60;

    /*//////////////////////////////////////////////////////////////
                                 STRUCT
    //////////////////////////////////////////////////////////////*/
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _poolManager,
        address _wrappedSubscription,
        address _usdc,
        address _defaultHooks,
        address _positionManager,
        address _permit2
    ) {
        i_poolManager = IPoolManager(_poolManager);
        i_wrappedSubscription = IWrappedSubscription(_wrappedSubscription);
        i_usdc = IERC20(_usdc);
        i_defaultHooks = IHooks(_defaultHooks);
        i_positionManager = PositionManager(payable(_positionManager));
        i_permit2 = IAllowanceTransfer(_permit2);
    }

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function createPool(
        uint24 swapFee,
        IHooks hooks,
        uint160 startingPrice,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 amount0Max,
        uint256 amount1Max,
        bytes memory hookData // encoded tokenId
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

        Currency currency0 = Currency.wrap(address(i_usdc));
        Currency currency1 = Currency.wrap(address(i_wrappedSubscription));

        // Ensure currencies are in ascending order
        if (currency0.toId() > currency1.toId()) {
            (currency0, currency1) = (currency1, currency0);
        }

        if (hooks == IHooks(address(0))) {
            // if no hooks are provided, use the default
            hooks = i_defaultHooks;
        }

        PoolKey memory pool = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: swapFee,
            tickSpacing: TICK_SPACING,
            hooks: hooks
        });

        // 3. Encode the initializePool parameters

        // the startingPrice is expressed as sqrtPriceX96: floor(sqrt(token1 / token0) * 2^96)
        // 79228162514264337593543950336 is the starting price for a 1:1 pool
        params[0] = abi.encodeWithSelector(
            i_positionManager.initializePool.selector,
            pool,
            startingPrice
        );

        // 4. Initialize the mint-liquidity parameters

        // The first command MINT_POSITION creates a new liquidity position
        // The second command SETTLE_PAIR indicates that tokens are to be paid by the caller, to create the position

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        // 5. Encode the MINT_POSITION parameters

        // pool the same PoolKey defined above, in pool-creation
        // tickLower and tickUpper are the range of the position, must be a multiple of pool.tickSpacing
        // liquidity is the amount of liquidity units to add, see LiquidityAmounts for converting token amounts to liquidity units
        // amount0Max and amount1Max are the maximum amounts of token0 and token1 the caller is willing to transfer
        // recipient is the address that will receive the liquidity position (ERC-721)
        // hookData is the optional hook data

        bytes[] memory mintParams = new bytes[](2);

        // Converts token amounts to liquidity units
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            TickMath.getSqrtPriceAtTick(TICK_LOWER),
            TickMath.getSqrtPriceAtTick(TICK_UPPER),
            token0Amount,
            token1Amount
        );

        mintParams[0] = abi.encode(
            pool,
            TICK_LOWER,
            TICK_UPPER,
            liquidity,
            amount0Max,
            amount1Max,
            // The recipient of the liquidity position is the caller, he owns the NFT
            msg.sender, // recipient
            hookData
        );

        // 6. Encode the SETTLE_PAIR parameters
        // Creating a position on a pool requires the caller to transfer `currency0` and `currency1` tokens
        mintParams[1] = abi.encode(pool.currency0, pool.currency1);

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
        IERC20(i_usdc).approve(address(i_permit2), type(uint256).max);
        IERC20(address(i_wrappedSubscription)).approve(
            address(i_permit2),
            type(uint256).max
        );

        // approve `PositionManager` as a spender
        IAllowanceTransfer(address(i_permit2)).approve(
            address(i_usdc),
            address(i_positionManager),
            type(uint160).max,
            type(uint48).max
        );
        IAllowanceTransfer(address(i_permit2)).approve(
            address(i_wrappedSubscription),
            address(i_positionManager),
            type(uint160).max,
            type(uint48).max
        );

        // 9. Execute the multicall
        PositionManager(i_positionManager).multicall(params);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
}
