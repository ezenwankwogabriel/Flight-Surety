import FlightSuretyApp from "../../build/contracts/FlightSuretyApp.json";
import FlightSuretyData from "../../build/contracts/FlightSuretyData.json";
import Config from "./config.json";
import Web3 from "web3";
import express from "express";
import _ from "lodash";
import cors from 'cors'

const config = Config["localhost"];
const web3 = new Web3(
  new Web3.providers.WebsocketProvider(config.url.replace("http", "ws"))
);
const registrationFee = web3.utils.toWei("10", "ether");
const flightSuretyApp = new web3.eth.Contract(
  FlightSuretyApp.abi,
  config.appAddress
);
const flightSuretyData = new web3.eth.Contract(
  FlightSuretyData.abi,
  config.dataAddress
)
  
const statuses = [0, 10, 20, 30, 40, 50];
const flightRecords = [];
const statusCode = 20;
const hash = {};
const gas = 100000000;

let accounts;
let airplanes;
let flights = ['Fly Airpeace', 'Dana Airways', 'Arik Air'];

web3.eth.getAccounts(function (error, result) {
  let counter = 1;

  web3.eth.defaultAccount = result[0];
  accounts = result.slice(1, 21);

  /** Register 20 oracles */
  accounts.forEach((account, i) => {
    flightSuretyApp.methods.registerOracle().send({from: account, value: registrationFee, gas}, (error) => {
      if (error) console.log(`error ${account, i} `, account, error)
    flightSuretyApp.methods
      .getMyIndexes()
      .call({ from: account })
      .then((indexes) => {
        hash[account] = indexes;
      }).catch(ex => console.log('error register', ex));
    });
  });

  // /** Fund default contract airplane */
  flightSuretyData.methods
    .fundAirline(web3.eth.defaultAccount)
    .send({ from: web3.eth.defaultAccount, value: registrationFee, gas });

  flights.forEach((flight) => {
    let payload = {
      airline: web3.eth.defaultAccount,
      flight,
      timestamp: Math.floor(Date.now() / 1000)
    }
    flightSuretyApp.methods
      .registerFlight(payload.airline, payload.flight, payload.timestamp)
      .send({ from: web3.eth.defaultAccount, gas }, (error, result) => {
          console.log('register flight', error, result)
      }).catch(ex => {
        console.log('exception handled by me', ex)
      })
  })

  flightSuretyApp.events.OracleRequest(
    {
      fromBlock: 0,
    },
    function (error, event) {
      if (error) return console.log(error);
      console.log("event", { ...event.returnValues });
      let { index, airline, flight, timestamp } = event.returnValues;
      // let count = 0;
      Object.keys(hash).forEach((key) => {
        if (hash[key].includes(index)) {
          // if (count++ < 5)
          flightSuretyApp.methods.submitOracleResponse(
            index,
            airline,
            flight,
            timestamp,
            _.sample(statuses) // random status code
          ).send({ from: key, gas }).catch(ex => {
            let key = Object.keys(ex.data)[0];
            console.log('exception handled by me', ex.data[key].reason)
          })
        }
      });
    }
  );

  flightSuretyApp.events.FlightRegistered({ fromBlock: 0 }, function (error, event) {
    let { flight, key, timestamp, airline } = event.returnValues;
    flightRecords.push({
      flight, key, timestamp, airline
    })
  })
  
  flightSuretyData.events.AirlineFunded({ fromBlock: 0 }, function (error, event) {
    if (error) return console.log('tx error', error)
    console.log('airline funded', event.returnValues)
  })
  
  flightSuretyData.events.InsurancePaid({ fromBlock: 0 }, function (error, event) {
    if (error) return console.log('tx error', error)
    console.log('paid insurance', error, event.returnValues)
  })
  
  flightSuretyApp.events.PayInsurance({ fromBlock: 0 }, function (error, event) {
    if (error) return console.log('tx error', error)
    console.log('Pay Insurance', error, event.returnValues)
  })
  
  flightSuretyData.events.CreditedInsuree({ fromBlock: 0 }, function (error, event) {
    if (error) return console.log('tx error', error)
    console.log('Credited Insurance', error, event.returnValues)
  })
  flightSuretyApp.events.OracleReport(
    {
      fromBlock: 0,
    },
    function (error, event) {
      if (error) console.log(error);
      console.log("report", event);
    }
  );
  
  flightSuretyApp.events.FlightStatusInfo({ fromBlock: 0 }, function(error, event) {
    if (error) console.log("error", event);
    console.log("status", event);
  });
});

  // flightSuretyApp.methods.submitOracleResponse(
  //   '100',
  //   '0x9929ac7008d901e705F80EF727A1c39906174d',
  //   'flight',
  //   '1619961766',
  //   '10',
  // ).call({from: '0x8857f5Bc6cF6f3840D839bE731223f7bB4dF058e' })

  // .send({from: '0x8857f5Bc6cF6f3840D839bE731223f7bB4dF058e', value: registrationFee, gas: 100000000}, (error, done) => {
  //   console.log('register', error, done)
  // })



const app = express();

app.get("/api", (req, res) => {
  res.send({
    message: "An API for use with your Dapp!",
  });
});

app.get("/api/flights", cors(), (req, res) => {
  res.send({ flights: flightRecords })
})

app.get("/api/wallet/:passengerId", cors(), (req, res) => {
  flightSuretyData.methods
  .viewPassengersFund()
  .call({ from: req.params.passengerId }, (error, result) => {
      console.log('passenger id', error, result);
      res.send('Successful')
  })
})

export default app;
