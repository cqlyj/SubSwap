// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract PaymentProcessor is Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IERC20 private immutable i_usdc;
    address private s_feeRecipient;
    uint256 private s_feePercentage = 3; // 3%
    uint256 private constant MAX_FEE_PERCENTAGE = 7; // 7%
    uint256 private constant FEE_PRECISION = 100;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error PaymentProcessor__FeePercentageExceedsMax();
    error PaymentProcessor__ZeroAddress();
    error PaymentProcessor__FailedToTransfer();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeePercentageUpdated(uint256 feePercentage);
    event FeeRecipientUpdated(address feeRecipient);
    event PaymentProcessed(
        address indexed payer,
        address indexed recipient,
        uint256 netAmount,
        uint256 fee
    );

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _usdc, address _feeRecipient) Ownable(msg.sender) {
        i_usdc = IERC20(_usdc);
        s_feeRecipient = _feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                            OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setFeePercentage(uint256 _feePercentage) external onlyOwner {
        if (_feePercentage > MAX_FEE_PERCENTAGE) {
            revert PaymentProcessor__FeePercentageExceedsMax();
        }

        s_feePercentage = _feePercentage;

        emit FeePercentageUpdated(_feePercentage);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) {
            revert PaymentProcessor__ZeroAddress();
        }

        s_feeRecipient = _feeRecipient;

        emit FeeRecipientUpdated(_feeRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                     EXTERNAL AND PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function processPayment(
        address payer,
        address recipient,
        uint256 amount
    ) external {
        uint256 fee = (amount * s_feePercentage) / 100;
        uint256 netAmount = amount - fee;

        bool successTransferFee = i_usdc.transferFrom(
            payer,
            s_feeRecipient,
            fee
        );
        bool successTransferSeller = i_usdc.transferFrom(
            payer,
            recipient,
            netAmount
        );

        if (!successTransferFee || !successTransferSeller) {
            revert PaymentProcessor__FailedToTransfer();
        }

        emit PaymentProcessed(payer, recipient, netAmount, fee);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getFeePercentage() external view returns (uint256) {
        return s_feePercentage;
    }

    function getFeeRecipient() external view returns (address) {
        return s_feeRecipient;
    }

    function getUsdc() external view returns (address) {
        return address(i_usdc);
    }

    function getMaxFeePercentage() external pure returns (uint256) {
        return MAX_FEE_PERCENTAGE;
    }

    function getFeePrecision() external pure returns (uint256) {
        return FEE_PRECISION;
    }
}
