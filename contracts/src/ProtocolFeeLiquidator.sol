// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ILiquidationRouter
 * @notice Minimal interface for executing token swaps.
 *         Implementations wrap a DEX router (Uniswap V2/V3, etc.).
 */
interface ILiquidationRouter {
    /**
     * @notice Swap exact tokens for output tokens/ETH.
     * @param tokenIn The token to sell.
     * @param amountIn The amount to sell.
     * @param recipient Where to send proceeds.
     * @return amountOut The amount of output received.
     */
    function liquidate(address tokenIn, uint256 amountIn, address recipient) external returns (uint256 amountOut);
}

/**
 * @title ProtocolFeeLiquidator
 * @notice Immutable, autonomous contract that sells protocol fee tokens on a fixed schedule.
 *
 * Schedule: 90-day lockup + 12-month linear unlock + permissionless auto-sell.
 *
 * Properties:
 *   - IMMUTABLE: No admin functions. No pause. No override. Once deployed, it runs to completion.
 *   - PERMISSIONLESS: Anyone can call liquidate() to trigger the sale of unlocked tokens.
 *   - PREDICTABLE: Anyone can calculate exactly how many tokens will be sold on any given day.
 *   - TRANSPARENT: Every sale is an on-chain swap through a known router.
 *
 * The contract receives 1% of tokens minted at transition. These tokens are governance-excluded
 * (enforced by StakeToken). The liquidation proceeds go to the protocol treasury.
 *
 * If the router fails (e.g., no liquidity), the tokens accumulate and can be sold later.
 * The contract never holds proceeds — they go directly to the treasury.
 *
 * Deployed per-project by the StakeVault during transition.
 */
contract ProtocolFeeLiquidator {
    // ============ Immutable State ============

    /// @notice The token being liquidated
    address public immutable token;

    /// @notice The swap router used for liquidation
    address public immutable router;

    /// @notice Where sale proceeds are sent
    address public immutable treasury;

    /// @notice Timestamp after which tokens begin unlocking
    uint64 public immutable lockupEnd;

    /// @notice Duration of the linear vesting period after lockup
    uint64 public immutable vestingDuration;

    /// @notice Timestamp when all tokens are fully unlocked
    uint64 public immutable vestingEnd;

    // ============ Mutable State ============

    /// @notice Total tokens to be liquidated (set once via initialize)
    uint256 public totalTokens;

    /// @notice Whether totalTokens has been set
    bool public initialized;

    /// @notice Total tokens released (sold) so far
    uint256 public totalReleased;

    // ============ Events ============

    event Liquidated(address indexed caller, uint256 tokensSold, uint256 proceedsReceived);

    // ============ Errors ============

    error NothingToLiquidate();
    error LiquidationFailed();
    error AlreadyInitialized();

    /**
     * @notice Deploy a new liquidator.
     * @param token_ The ERC-20 token to liquidate.
     * @param router_ The liquidation router (DEX wrapper).
     * @param treasury_ Where proceeds go.
     * @param lockupEnd_ When the lockup period ends (tokens start unlocking).
     * @param vestingDuration_ How long the linear vesting lasts after lockup.
     *
     * @dev Tokens must be transferred to this contract after deployment, then initialize()
     *      must be called to snapshot the balance as totalTokens. The StakeVault handles both
     *      steps atomically during transition. If initialize() is never called, liquidate() reverts.
     */
    constructor(address token_, address router_, address treasury_, uint64 lockupEnd_, uint64 vestingDuration_) {
        token = token_;
        router = router_;
        treasury = treasury_;
        lockupEnd = lockupEnd_;
        vestingDuration = vestingDuration_;
        vestingEnd = lockupEnd_ + vestingDuration_;
    }

    /**
     * @notice Initialize totalTokens from the current balance. Called once after tokens are transferred.
     *         Permissionless — anyone can call it, but it can only be set once.
     */
    function initialize() external {
        if (initialized) revert AlreadyInitialized();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance == 0) revert NothingToLiquidate();
        totalTokens = balance;
        initialized = true;
    }

    // ============ Core Functions ============

    /**
     * @notice Calculate how many tokens are currently releasable (unlocked but not yet sold).
     * @return amount The number of tokens available for liquidation.
     */
    function releasable() public view returns (uint256) {
        if (!initialized) return 0;
        if (block.timestamp < lockupEnd) return 0;

        uint256 totalUnlocked;
        if (block.timestamp >= vestingEnd) {
            totalUnlocked = totalTokens;
        } else {
            uint256 elapsed = block.timestamp - lockupEnd;
            totalUnlocked = (totalTokens * elapsed) / vestingDuration;
        }

        return totalUnlocked - totalReleased;
    }

    /**
     * @notice Sell all currently releasable tokens through the router.
     *         Permissionless — anyone can call this. MEV bots, keepers, the protocol team.
     *         The outcome is always the same: tokens are sold, proceeds go to treasury.
     *
     * @return tokensSold The number of tokens sold in this call.
     * @return proceeds The amount of output received from the swap.
     */
    function liquidate() external returns (uint256 tokensSold, uint256 proceeds) {
        tokensSold = releasable();
        if (tokensSold == 0) revert NothingToLiquidate();

        totalReleased += tokensSold;

        // Approve router to spend tokens
        IERC20(token).approve(router, tokensSold);

        // Execute swap — proceeds go directly to treasury
        proceeds = ILiquidationRouter(router).liquidate(token, tokensSold, treasury);

        emit Liquidated(msg.sender, tokensSold, proceeds);
    }

    // ============ View Functions ============

    /**
     * @notice Get the full liquidation schedule.
     * @return _totalTokens Total tokens to be liquidated.
     * @return _totalReleased Tokens already liquidated.
     * @return _releasable Tokens currently available for liquidation.
     * @return _lockupEnd When lockup ends.
     * @return _vestingEnd When all tokens are fully unlocked.
     * @return _percentComplete Percentage complete (basis points, 10000 = 100%).
     */
    function schedule()
        external
        view
        returns (
            uint256 _totalTokens,
            uint256 _totalReleased,
            uint256 _releasable,
            uint64 _lockupEnd,
            uint64 _vestingEnd,
            uint16 _percentComplete
        )
    {
        _totalTokens = totalTokens;
        _totalReleased = totalReleased;
        _releasable = releasable();
        _lockupEnd = lockupEnd;
        _vestingEnd = vestingEnd;

        if (totalTokens == 0) _percentComplete = 0;
        else _percentComplete = uint16((totalReleased * BPS_BASE) / totalTokens);
    }

    uint16 private constant BPS_BASE = 10_000;
}
