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
        Completed
    }

    enum SaleTech {
        ThirdParty,
        Trustless
    }

    // 3rd party can help resolve disputes offchain, and then take a cut of the sale price as a fee for their service (e.g. 5%)
    struct Sale {
        uint price;
        Status status;
        uint feedID;
        uint disputeTime;
        bool isDisputed;
        // [0] seller, [1] buyer votes
        address[2] disputeResolver;
        SaleTech tech;
    }

    IMorhpeus internal constant morpheus = IMorhpeus(address(1337));
    uint constant DISPUTE_TIME = 7 days;
    IERC20 internal immutable token;
    // seller => buyer => sale
    mapping(address => mapping(address => Sale)) internal sales;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function createSale(address seller, uint price, SaleTech tech) internal {
        if (sales[seller][msg.sender].status != Status.Uninitialized)
            revert("Already selling");

        sales[seller][msg.sender] = Sale({
            price: price,
            status: Status.PendingCompletion,
            feedID: 0,
            disputeTime: 0,
            isDisputed: false,
            disputeResolver: [address(0), address(0)],
            tech: tech
        });
        token.transferFrom(msg.sender, address(this), price);
    }

    // todo: add logic to send the disputeResolver 5% of the sale price after finish
    function createThirdPartySale(address seller, uint price) external {
        createSale(seller, price, SaleTech.ThirdParty);
    }

    // todo: add logic to take priceX2 from both buyer and seller
    function createTrustlessSale(address seller, uint price) external {
        createSale(seller, price, SaleTech.Trustless);
    }

    // the seller can cancel the sale anytime before completion
    function cancelSale(address buyer) external {
        Sale memory sale = sales[msg.sender][buyer];
        if (sale.status != Status.PendingCompletion) revert("Not selling");
        if (msg.sender != msg.sender) revert("Not seller"); // not really necessary
        token.transfer(buyer, sale.price);
        delete sales[msg.sender][buyer];
    }

    // after CreateSale()
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

    // after RequestCompletion()
    function completeSale(address seller, address buyer) external {
        Sale memory sale = sales[seller][buyer];

        if (sale.disputeTime != 0 && sale.disputeTime > block.timestamp)
            revert("Dispute time not over");
        if (sale.status != Status.PendingCompletion) revert("Not selling");
        (uint256 value, , , ) = morpheus.getFeed(sale.feedID);
        if (value != 1) revert("Not completed");

        sales[seller][buyer].status = Status.Completed;
        sales[seller][buyer].disputeTime = block.timestamp + DISPUTE_TIME;

        token.transfer(seller, sale.price);
    }

    // after CompleteSale()
    function withdraw(address seller, address buyer) external {
        Sale memory sale = sales[seller][buyer];
        if (sale.status != Status.Completed) revert("Not completed");
        if (msg.sender != seller) revert("Not seller");
        if (sale.isDisputed) revert("Disputed");
        if (sale.disputeTime > block.timestamp) revert("Dispute time not over");

        token.transfer(seller, sale.price);
        delete sales[seller][buyer];
    }

    function addDisputeResolver(
        address seller,
        address buyer,
        address resolver
    ) external {
        Sale memory sale = sales[seller][buyer];
        if (sale.status != Status.PendingCompletion) revert("Not selling");

        if (msg.sender != seller && msg.sender != buyer)
            revert("Not seller or buyer");

        if (!sale.isDisputed) revert("Not Disputed");

        if (
            sale.disputeResolver[0] != address(0) &&
            sale.disputeResolver[0] == sale.disputeResolver[1]
        ) revert("Already Set");

        if (msg.sender == seller) {
            sales[seller][buyer].disputeResolver[0] = resolver;
        } else {
            sales[seller][buyer].disputeResolver[1] = resolver;
        }
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

    function disputeSale(address seller) external {
        Sale storage sale = sales[seller][msg.sender];
        if (sale.status != Status.PendingCompletion) revert("Not selling");
        sale.isDisputed = true;
    }

    function getSale(
        address seller,
        address buyer
    ) public view returns (Sale memory) {
        return sales[seller][buyer];
    }
}
