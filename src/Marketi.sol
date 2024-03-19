// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
}

interface IMorhpeus {
    function requestFeed(
        address[] memory morpheus,
        string memory APIendpoint,
        string memory APIendpointPath,
        uint256 decimals,
        uint256[] memory bounties
    ) external returns (uint256[] memory);
    function requestFeed(
        address[] memory morpheus,
        string memory APIendpoint,
        string memory APIendpointPath,
        uint256 decimals
    ) external returns (uint256[] memory);
    function getFeed(
        uint256 feedID
    )
        external
        view
        returns (
            uint256 value,
            uint256 decimals,
            uint256 timestamp,
            string memory valStr
        );
}
/**
 * @title Marketi
 * @author Some people names
 * @notice A simple market contract
 * @dev This contract is a simple market contract that allows users to create sales and complete them, where Morpheus oracle is used as the source of truth in the completion of the sale.
 *
 * Future Features:
 * - Batch request and completion
 * - Cancellation
 * - Events
 *
 */
contract Marketi {
    enum Status {
        Uninitialized,
        PendingCompletion,
        // DisputePeriod,
        Completed
        // Cancelled // Cancellation should move to Uninitialized state
    }

    struct Sale {
        address seller;
        uint price;
        Status status;
        uint feedID;
        uint disputeTime;
        bool isDisputed;
    }
    address constant MORPHEUS = address(1337);
    IERC20 internal token;
    IMorhpeus internal constant morpheus = IMorhpeus(MORPHEUS);
    uint constant DISPUTE_TIME = 7 days;
    // seller => buyer => sale
    mapping(address => mapping(address => Sale)) internal sales;

    modifier onlySeller(address seller, address buyer) {
        if (msg.sender != seller) revert("Not seller");
        _;
    }

    modifier onlyBuyer(address seller, address buyer) {
        if (msg.sender != buyer) revert("Not buyer");
        _;
    }

    modifier onlyPending(address seller, address buyer) {
        if (sales[seller][buyer].status != Status.PendingCompletion)
            revert("Not selling");
        _;
    }

    constructor(address _token) {
        token = IERC20(_token);
    }

    function createSale(address seller, uint price) public {
        if (sales[seller][msg.sender].status != Status.Uninitialized)
            revert("Already selling");

        sales[seller][msg.sender] = Sale({
            seller: seller,
            price: price,
            status: Status.PendingCompletion,
            feedID: 0,
            disputeTime: 0,
            isDisputed: false
        });
        token.transferFrom(msg.sender, address(this), price);
    }

    // the seller can cancel the sale anytime
    // function cancelSale(address seller, address buyer) public {
    //     Sale storage sale = sales[seller][buyer];
    //     if (sale.status != Status.Pending) revert("Not selling");
    //     if (msg.sender != seller) revert("Not seller"); // not really necessary
    //     token.transfer(buyer, sale.price);
    //     delete sales[seller][buyer];
    // }

    function requestCompletion(address seller, address buyer) external {
        Sale storage sale = sales[seller][buyer];
        if (sale.status != Status.PendingCompletion) revert("Not selling");
        if (msg.sender != seller) revert("Not seller");

        address[] memory _morpheus = new address[](1);
        _morpheus[0] = address(this);
        uint256[] memory feedIDs = morpheus.requestFeed(
            _morpheus,
            "https://api.coingecko.com/api/v3/simple/price",
            "ethereum",
            1e18
        );
        sale.feedID = feedIDs[0];
    }

    function completeSale(address seller, address buyer) external {
        Sale storage sale = sales[seller][buyer];

        if (sale.disputeTime < block.timestamp) revert("Dispute time not over");
        if (sale.status != Status.PendingCompletion) revert("Not selling");
        (uint256 value, , , ) = morpheus.getFeed(sale.feedID);
        if (value < sale.price) revert("Price not met");
        sale.status = Status.Completed;
        sale.disputeTime = block.timestamp + DISPUTE_TIME;

        token.transfer(seller, sale.price);
    }

    function withdraw(address seller, address buyer) external {
        Sale storage sale = sales[seller][buyer];
        if (sale.status != Status.Completed) revert("Not completed");
        if (msg.sender != seller) revert("Not seller");
        if (sale.isDisputed) revert("Disputed");
        if (sale.disputeTime < block.timestamp) revert("Dispute time not over");
        token.transfer(seller, sale.price);
        delete sales[seller][buyer];
    }

    // function requestCompletionBatch(
    //     address seller,
    //     address[] memory buyers
    // ) public {
    //     for (uint i = 0; i < buyers.length; i++) {
    //         requestCompletion(seller, buyers[i]);
    //     }
    // }

    // function completeSaleBatch(address seller, address[] memory buyers) public {
    //     for (uint i = 0; i < buyers.length; i++) {
    //         completeSale(seller, buyers[i]);
    //     }
    // }

    function disputeSale(address seller, address buyer) external {
        Sale storage sale = sales[seller][buyer];
        if (sale.status != Status.PendingCompletion) revert("Not selling");
        if (msg.sender != buyer) revert("Not buyer");
        sale.isDisputed = true;
    }

    function getSale(
        address seller,
        address buyer
    ) public view returns (Sale memory) {
        return sales[seller][buyer];
    }
}
