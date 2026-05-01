// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract VestigeIndexVIGIX is ERC20, Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    uint256 public constant BPS = 10_000;

    uint256 public constant BUY_FEE = 15;
    uint256 public constant SELL_FEE = 25;

    address public constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    uint256 public constant BASE_PRICE = 0.10 ether;
    uint256 public constant STEP_PRICE = 0.025 ether;

    uint256 public constant EARLY_STEP = 250_000 ether;
    uint256 public constant LATE_STEP = 1_000_000 ether;
    uint256 public constant TRANSITION = 2_500_000 ether;

    uint256 public constant INTRA_STEP_PREMIUM = 0.015 ether;

    address public feeWallet;

    error Slippage();
    error ZeroAmount();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientReserve();

    event Bought(address indexed user, uint256 usdcIn, uint256 tokensOut, uint256 fee);
    event Sold(address indexed user, uint256 tokensIn, uint256 usdcOut, uint256 fee);
    event FeeWalletUpdated(address indexed oldWallet, address indexed newWallet);

    constructor()
        ERC20("Vestige Index", "VIGIX")
        Ownable(msg.sender)
    {
        feeWallet = 0x826727e3f91E5c17Ec8342f0c1282a4877F747dC;
    }

    function setFeeWallet(address newWallet) external onlyOwner {
        if (newWallet == address(0)) revert ZeroAddress();

        address oldWallet = feeWallet;
        feeWallet = newWallet;

        emit FeeWalletUpdated(oldWallet, newWallet);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _stepSize(uint256 supply) internal pure returns (uint256) {
        return supply < TRANSITION ? EARLY_STEP : LATE_STEP;
    }

    function _stepIndex(uint256 supply) internal pure returns (uint256) {
        if (supply < TRANSITION) {
            return supply / EARLY_STEP;
        }

        return (TRANSITION / EARLY_STEP) + ((supply - TRANSITION) / LATE_STEP);
    }

    function _stepStart(uint256 supply) internal pure returns (uint256) {
        if (supply < TRANSITION) {
            return (supply / EARLY_STEP) * EARLY_STEP;
        }

        return TRANSITION + (((supply - TRANSITION) / LATE_STEP) * LATE_STEP);
    }

    function _stepEnd(uint256 supply) internal pure returns (uint256) {
        return _stepStart(supply) + _stepSize(supply);
    }

    function priceAt(uint256 supply) public pure returns (uint256) {
        uint256 step = _stepSize(supply);
        uint256 start = _stepStart(supply);
        uint256 progress = supply - start;

        uint256 baseStepPrice = BASE_PRICE + (_stepIndex(supply) * STEP_PRICE);
        uint256 premium = Math.mulDiv(INTRA_STEP_PREMIUM, progress, step);

        return baseStepPrice + premium;
    }

    function _to18(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * (10 ** (18 - decimals));
        return amount / (10 ** (decimals - 18));
    }

    function _from18(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals < 18) return amount / (10 ** (18 - decimals));
        return amount * (10 ** (decimals - 18));
    }

    function _costWithinStep(
        uint256 fromSupply,
        uint256 toSupply
    ) internal pure returns (uint256 usd18) {
        if (toSupply <= fromSupply) return 0;

        uint256 start = _stepStart(fromSupply);
        uint256 step = _stepSize(fromSupply);

        uint256 baseStepPrice = BASE_PRICE + (_stepIndex(fromSupply) * STEP_PRICE);

        uint256 x0 = fromSupply - start;
        uint256 x1 = toSupply - start;
        uint256 amount = toSupply - fromSupply;

        uint256 linearCost = Math.mulDiv(amount, baseStepPrice, 1 ether);

        uint256 premiumArea = x1 * x1 - x0 * x0;
        uint256 premiumCost = Math.mulDiv(
            INTRA_STEP_PREMIUM,
            premiumArea,
            2 * step * 1 ether
        );

        return linearCost + premiumCost;
    }

    function _costBetween(
        uint256 fromSupply,
        uint256 toSupply
    ) internal pure returns (uint256 usd18) {
        uint256 supply = fromSupply;

        while (supply < toSupply) {
            uint256 end = _stepEnd(supply);
            if (end > toSupply) end = toSupply;

            usd18 += _costWithinStep(supply, end);
            supply = end;
        }
    }

    function _buyExact(
        uint256 supply,
        uint256 usd18
    ) internal pure returns (uint256 tokensOut) {
        uint256 remainingUsd = usd18;

        while (remainingUsd > 0) {
            uint256 boundary = _stepEnd(supply);
            uint256 costToBoundary = _costWithinStep(supply, boundary);

            if (remainingUsd >= costToBoundary) {
                tokensOut += boundary - supply;
                remainingUsd -= costToBoundary;
                supply = boundary;
            } else {
                uint256 low = 0;
                uint256 high = boundary - supply;

                while (low < high) {
                    uint256 mid = (low + high + 1) / 2;
                    uint256 cost = _costWithinStep(supply, supply + mid);

                    if (cost <= remainingUsd) {
                        low = mid;
                    } else {
                        high = mid - 1;
                    }
                }

                tokensOut += low;
                break;
            }
        }
    }

    function _sellExact(
        uint256 supply,
        uint256 amount
    ) internal pure returns (uint256 usd18) {
        return _costBetween(supply - amount, supply);
    }

    function previewBuy(uint256 usdcAmount) external view returns (uint256 tokensOut) {
        uint8 decimals = IERC20Metadata(USDC).decimals();

        uint256 fee = (usdcAmount * BUY_FEE) / BPS;
        uint256 net = usdcAmount - fee;

        return _buyExact(totalSupply(), _to18(net, decimals));
    }

    function previewSell(uint256 tokenAmount) external view returns (uint256 usdcOut) {
        uint8 decimals = IERC20Metadata(USDC).decimals();

        uint256 usd18 = _sellExact(totalSupply(), tokenAmount);
        uint256 gross = _from18(usd18, decimals);

        uint256 fee = (gross * SELL_FEE) / BPS;

        return gross - fee;
    }

    function buy(uint256 amount, uint256 minOut) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        IERC20 usdc = IERC20(USDC);
        uint8 decimals = IERC20Metadata(USDC).decimals();

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        uint256 fee = (amount * BUY_FEE) / BPS;
        uint256 net = amount - fee;

        uint256 out = _buyExact(totalSupply(), _to18(net, decimals));

        if (out < minOut) revert Slippage();

        if (fee > 0) {
            usdc.safeTransfer(feeWallet, fee);
        }

        _mint(msg.sender, out);

        emit Bought(msg.sender, amount, out, fee);
    }

    function sell(uint256 amount, uint256 minOut) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();

        IERC20 usdc = IERC20(USDC);
        uint8 decimals = IERC20Metadata(USDC).decimals();

        uint256 usd18 = _sellExact(totalSupply(), amount);
        uint256 gross = _from18(usd18, decimals);

        uint256 fee = (gross * SELL_FEE) / BPS;
        uint256 net = gross - fee;

        if (net < minOut) revert Slippage();

        uint256 balance = usdc.balanceOf(address(this));
        if (balance < net + fee) revert InsufficientReserve();

        _burn(msg.sender, amount);

        if (fee > 0) {
            usdc.safeTransfer(feeWallet, fee);
        }

        usdc.safeTransfer(msg.sender, net);

        emit Sold(msg.sender, amount, net, fee);
    }
}