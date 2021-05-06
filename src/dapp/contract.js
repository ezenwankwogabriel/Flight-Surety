import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import FlightSuretyData from '../../build/contracts/FlightSuretyData.json';
import Config from './config.json';
import Web3 from 'web3';
import axios from 'axios';

export default class Contract {
    constructor(network, callback) {

        let config = Config[network];
        this.web3 = new Web3(new Web3.providers.HttpProvider(config.url));
        this.flightSuretyApp = new this.web3.eth.Contract(FlightSuretyApp.abi, config.appAddress);
        this.flightSuretyData = new this.web3.eth.Contract(FlightSuretyData.abi, config.dataAddress);
        this.initialize(callback);
        this.owner = null;
        this.insuranceAmount = this.web3.utils.toWei("0.1", "ether");
        this.airlines = [];
        this.passengers = [];
    }

    initialize(callback) {
        this.web3.eth.getAccounts((error, accts) => {
           
            this.owner = accts[0];

            let counter = 1;
            
            while(this.airlines.length < 5) {
                this.airlines.push(accts[counter++]);
            }

            while(this.passengers.length < 5) {
                this.passengers.push(accts[counter++]);
            }

            axios.get('http://localhost:3000/api/flights')
                .then(resp => {
                    this.flights = resp.data.flights;
                    var select = document.getElementById("select-flight"); 
                    for (var i = 0; i < this.flights.length; i++) {
                        var opt = this.flights[i];
                        var el = document.createElement('option');
                        el.textContent = opt.flight;
                        el.value = opt.key;
                        select.appendChild(el);
                    }

                    callback();
                }).catch(ex => {
                    console.log(ex);
                    callback();
                })

        });
    }

    isOperational(callback) {
       let self = this;
       self.flightSuretyData.methods
            .isOperational()
            .call({ from: self.owner}, callback);
    }

    fetchFlightStatus(key, callback) {
        let self = this;
        // let payload = {
        //     airline: self.airlines[0],
        //     flight: flight,
        //     timestamp: Math.floor(Date.now() / 1000)
        // } 
        self.flightSuretyApp.methods
            .fetchFlightStatus(key)
            .send({ from: this.passengers[0] }, (error, result) => {
                if (error) return callback(error);
                setTimeout(() => {
                    self.flightSuretyApp.methods.fetchFlightStatusCode(key)
                        .call({ from: this.passengers[0] }, (error, status) => {
                            if (status === '20') {
                                console.log('im here')
                                self.flightSuretyData.methods.viewPassengersFund()
                                .call({ from: this.passengers[0] }, (error, funds) => {
                                        console.log(funds)
                                        callback(error, {funds: this.web3.utils.fromWei(funds, 'ether'), status});
                                    })
                            } else {
                                callback(error, {status});
                            }
                        })
                }, 2000)
            });
    }

    payInsurance(value, amount, callback) {
        let self = this;
        let flight = this.flights.find(flight => flight.key === value);
        self.flightSuretyData.methods
            .buyInsurance(flight.key, flight.airline)
            .send({ from: this.passengers[0], value:  this.web3.utils.toWei(amount, "ether") }, (error, result) => {
                if (error) return callback(error)

                self.flightSuretyData.methods.passengerInsured(flight.key)
                    .call({ from: this.passengers[0] }, (iError, details) => {
                        if (details[0]) {
                            details[1] = this.web3.utils.fromWei(details[1], "ether")
                        }
                        callback(iError, details);
                    })
            })
    }

    viewWallet(callback) {
        let self = this;
        self.flightSuretyData.methods
            .viewPassengersFund()
            .call({ from: this.passengers[0] }, (error, result) => {
                callback(error, result)
            })
    } 
}