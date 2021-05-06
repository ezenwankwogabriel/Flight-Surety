pragma solidity >=0.4.25;
// pragma experimental ABIencoderV2;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    FlightData flightSuretyData;

    mapping(address => address[]) multicalls; //  voters by airline voted for

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    address private contractOwner; // Account used to deploy contract

    struct Flight {
        bool isRegistered;
        uint256 statusCode;
        uint256 updatedTimestamp;
        string flight;
        uint8 index;
        address airline;
    }
    mapping(bytes32 => Flight) private flights;

    event FlightRegistered(string flight, bytes32 key, uint256 timestamp, address airline);
    event PayInsurance(address airline, string flight);
    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        // Modify to call data contract's status
        require(true, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
     * @dev Contract constructor
     *
     */
    constructor(address dataContract) public {
        contractOwner = msg.sender;
        flightSuretyData = FlightData(dataContract);
        flightSuretyData.registerAirline(msg.sender);
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *
     */

    function registerAirline(address airline)
        external
        returns (bool success, uint256 votes)
    {
        require(!flightSuretyData.isAirline(airline), 'Airline already registered');
        require(flightSuretyData.isFundedAirline(msg.sender), 'Airplane not yet funded, hence cannot participate in contract');
        uint256 increment = 1;
        uint256 airlineCounter = flightSuretyData.airlineCounter();
        // register three more but must be by an existing airline
        
        if (airlineCounter < 5) {
            require(flightSuretyData.isAirline(msg.sender), 'Airline must be registered only by existing airlines');

            flightSuretyData.registerAirline(airline);
        } else if (airlineCounter >= 5) {
            bool isDuplicate = false;
            
            
            for (uint x = 0; x < multicalls[airline].length; x++) {
                if (multicalls[airline][x] == msg.sender) {
                    isDuplicate = true;
                }
            }
            require(!isDuplicate, 'Caller has already voted to this airline previously');

            multicalls[airline].push(msg.sender);

            uint256 M = airlineCounter.div(2);

            if (multicalls[airline].length > M) {
                flightSuretyData.registerAirline(airline);
                multicalls[airline] = new address[](0);
            }
        }

        // use multi-party consensus to add more
        return (success, 0);
    }

    /**
     * @dev Register a future flight for insuring.
     *
     */


    function registerFlight(address airline, string flight, uint256 timestamp) external {
        uint8 index = getRandomIndex(msg.sender);

        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        require(!flights[key].isRegistered, 'Flight is already registered');

        flights[key].isRegistered = true;
        flights[key].flight = flight;
        flights[key].updatedTimestamp = timestamp;
        flights[key].airline = airline;
        flights[key].index = index;
        
        emit FlightRegistered(flight, key, timestamp, airline);
    }

    /**
     * @dev Called after oracle has updated flight status
     *
     */

    function processFlightStatus(
        uint8 index,
        address airline,
        string memory flight,
        uint256 timestamp,
        uint8 statusCode
    ) internal {
        bytes32 key = getFlightKey(index, airline, flight, timestamp);
        flights[key].statusCode = statusCode;

        if (statusCode == STATUS_CODE_LATE_AIRLINE) {
            flightSuretyData.creditInsuree(key, airline);
            emit PayInsurance(airline, flight);
        }
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(
        bytes32 key
        // address airline,
        // string flight,
        // uint256 timestamp
    ) external {
        // uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        // bytes32 key =
        //     keccak256(abi.encodePacked(index, airline, flight, timestamp));
        uint8 index = flights[key].index;
        address airline = flights[key].airline;
        string flight = flights[key].flight;
        uint256 timestamp = flights[key].updatedTimestamp;
        oracleResponses[key] = ResponseInfo({
            requester: msg.sender,
            isOpen: true
        });

        emit OracleRequest(index, airline, flight, timestamp, key);
    }

    // region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester; // Account that requested status
        bool isOpen; // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses; // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    event OracleReport(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status,
        bytes32 key
    );

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp,
        bytes32 key
    );

    // Register an oracle with the contract
    function registerOracle() external payable returns (uint[] memory) {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function getMyIndexes() external view returns (uint8[3]) {
        require(
            oracles[msg.sender].isRegistered,
            "Not registered as an oracle"
        );

        return oracles[msg.sender].indexes;
    }
    
    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    ) external {
        require(
            (oracles[msg.sender].indexes[0] == index) ||
                (oracles[msg.sender].indexes[1] == index) ||
                (oracles[msg.sender].indexes[2] == index),
            "Index does not match oracle request"
        );

        bytes32 key =
            keccak256(abi.encodePacked(index, airline, flight, timestamp));
        require(
            oracleResponses[key].isOpen,
            "Flight or timestamp do not match oracle request"
        );

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode, key);
        if ( oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES ) {
            oracleResponses[key].isOpen = false;
            
            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(index, airline, flight, timestamp, statusCode);
        }
    }

    function fetchFlightStatusCode(bytes32 key) external view returns (uint256) {
        return flights[key].statusCode;
    }

    function getFlightKey(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(index, airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account) internal returns (uint8[3]) {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random =
            uint8(
                uint256(
                keccak256(
                        abi.encodePacked(
                            blockhash(block.number - nonce++),
                            account
                        )
                    )
                ) % maxValue
            );

        if (nonce > 250) {
            nonce = 0; // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

}



contract FlightData {
    function isAirline(address airline) public view returns (bool) {}
    function registerAirline(address airline) external {}
    function airlineCounter() public view returns (uint) {}
    function isFundedAirline(address airline) public view returns (bool) {}
    function creditInsuree(bytes32 key, address airline) external {}
}