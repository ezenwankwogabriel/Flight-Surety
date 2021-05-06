pragma solidity >=0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false

    uint256 public airlineCounter = 0;

    struct Airline {
        bool isRegistered;
        bool isFunded;
        uint amount;
    }

    mapping(address => bool) private authorizedUser;
    event Registered(bool isRegistered);
    event InsurancePaid(bytes32 key, uint256 amount, address insuree);
    event CreditedInsuree(bytes32 key, uint256 amount, address passenger, uint256 airlineAmount);
    event AirlineFunded(address airline, uint256 funds);

    mapping(address => Airline) public airlines;

    address[] fundedAirlines = new address[](0);

    struct FlightInsurance {
        bool isPaidOut;
        address[] passengers;
        mapping(address => uint256) purchasedAmount;
    }
    
    mapping(bytes32 => FlightInsurance) flightInsurances;
    mapping(address => uint256) private passengerBalance;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor() public {
        contractOwner = msg.sender;
    }

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
        require(operational, "Contract is currently not operational");
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
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */

    function isOperational() public view returns (bool) {
        return operational;
    }

    function authorizeUser(address user) external requireIsOperational {
        authorizedUser[user] = true;
    }

    function deauthorizeUser(address user) external requireIsOperational {
        delete authorizedUser[user];
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */

    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    function isAirline(address airline) public view returns (bool) {
        return airlines[airline].isRegistered;
    }

    function isFundedAirline(address airline) public view returns (bool) {
        return airlines[airline].isFunded;
    }

    function airlineCount() public view returns (uint256) {
        return airlineCounter;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */

    function registerAirline(address airline) external {
        require(!airlines[airline].isRegistered, 'Airline is already registered');
        airlines[airline] = Airline({
            isRegistered: true,
            isFunded: false,
            amount: 0
        });
        airlineCounter = airlineCounter.add(1);
        emit Registered(true);
    }

    function removeAirline(address airline) external requireContractOwner {
        require(airline != contractOwner, 'Cannot remove admin airline');
        delete airlines[airline];
        airlineCounter = airlineCounter.sub(1);
    }

    function fundAirline(address airline) public payable {
        require(msg.value >= 10 ether, 'Fund must be at least 10 ether');
        require(!airlines[airline].isFunded, 'Airline is already funded');

        airlines[airline].isFunded = true;
        airlines[airline].amount = msg.value;
        
        fundedAirlines.push(airline);

        emit AirlineFunded(airline, msg.value);
    }

    /**
     * @dev Buy insurance for a flight
     *
     */

    function buyInsurance(bytes32 key, address airline) external payable requireIsOperational {
        airlines[airline].amount.add(msg.value);
        flightInsurances[key].purchasedAmount[msg.sender] = msg.value;
        flightInsurances[key].passengers.push(msg.sender);

        emit InsurancePaid(key, msg.value, msg.sender);
    }

    /**
     *  @dev Credits payouts to insurees
     */
    function creditInsuree(bytes32 key, address airline) external requireIsOperational {
        require(!flightInsurances[key].isPaidOut, 'Flight insurance has been paid out');
        
        address[] storage passengers = flightInsurances[key].passengers;
        for (uint i = 0; i < passengers.length; i++) {
            address passenger = passengers[i];
            uint256 purchasedAmount = flightInsurances[key].purchasedAmount[passenger];
            uint256 payoutAmount = purchasedAmount.mul(3).div(2);
            passengerBalance[passenger] = payoutAmount;
            airlines[airline].amount.sub(payoutAmount);
        }
        flightInsurances[key].isPaidOut = true;

        emit CreditedInsuree(key, payoutAmount, passenger, airlines[airline].amount);
    }

    function passengerInsured(bytes32 key) external view returns(bool, uint256) {
        uint256 amountInsured = flightInsurances[key].purchasedAmount[msg.sender];
        bool insured = amountInsured > 0;

        return (insured, amountInsured);
    }

    function viewPassengersFund() external view returns(uint256){
        return passengerBalance[msg.sender];
    }
    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function pay(uint256 amount, address passenger) external requireIsOperational {
        passengerBalance[passenger] = passengerBalance[passenger].sub(amount);
        passenger.transfer(amount);
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */

    function fund() public payable {}

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
     * @dev Fallback function for funding smart contract.
     *
     */
    function() external payable {
        fund();
    }
}
