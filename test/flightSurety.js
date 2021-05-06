var Test = require("../config/testConfig.js");
var BigNumber = require("bignumber.js");

contract("Flight Surety Tests", async (accounts) => {
  var config;
  before("setup contract", async () => {
    config = await Test.Config(accounts);
    // await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
  });

  /****************************************************************************************/
  /* Operations and Settings                                                              */
  /****************************************************************************************/

  it(`(multiparty) has correct initial isOperational() value`, async function () {
    // Get operating status
    let status = await config.flightSuretyData.isOperational.call();
    assert.equal(status, true, "Incorrect initial operating status value");
  });

  it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {
    // Ensure that access is denied for non-Contract Owner account
    let accessDenied = false;
    try {
      await config.flightSuretyData.setOperatingStatus(false, {
        from: config.testAddresses[2],
      });
    } catch (e) {
      console.log(e.message)
      accessDenied = true;
    }
    assert.equal(accessDenied, true, "Access restricted to Contract Owner");
  });

  it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {
    // Ensure that access is allowed for Contract Owner account
    let accessDenied = false;
    try {
      await config.flightSuretyData.setOperatingStatus(false);
    } catch (e) {
      accessDenied = true;
    }
    assert.equal(
      accessDenied,
      false,
      "Access not restricted to Contract Owner"
    );
  });

  it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {
    await config.flightSuretyData.setOperatingStatus(false);

    let reverted = false;
    try {
      await config.flightSurety.setTestingMode(true);
    } catch (e) {
      reverted = true;
    }
    assert.equal(reverted, true, "Access not blocked for requireIsOperational");

    // Set it back for other tests to work
    await config.flightSuretyData.setOperatingStatus(true);
  });

  it("(airline) registers first airline on deployment", async () => {
    const counter = await config.flightSuretyData.airlineCounter.call();
    assert.equal(counter, 1, "Airline count does not match");
  });

  // it("(airline) Airline registration fails when not registered by existing airline and airlines are less than 5", async () => {
  //   let airline1 = accounts[1];
  //   let airline2 = accounts[2];
  //   let responseText;
  //   let failedText = "Returned error: sender account not recognized";
  //   try {
  //     await config.flightSuretyData.registerAirline(airline1, { from: airline2 });
  //   } catch (e) {
  //     responseText = e.message;
  //   }
  //   assert.equal(responseText, failedText, "Registration can only be done by exising airline");
  // });

  it('(airline) Only existing airline may register a new airline until there are at least four airlines registered', async () => {
    let airline1 = accounts[0];
    let airline2 = accounts[3];
    let airline3 = accounts[4];
    let airline4 = accounts[5];
    let airline5 = accounts[6];

    const payment = web3.utils.toWei('10', 'ether');

    try {
      await config.flightSuretyApp.registerAirline(airline2)
      await config.flightSuretyData.fundAirline(airline2, { value: payment });

      await config.flightSuretyApp.registerAirline(airline3, { from: airline2 })
      await config.flightSuretyApp.registerAirline(airline4, { from: airline2 })
      await config.flightSuretyApp.registerAirline(airline5, { from: airline2 })
    } catch(ex) {
      throw ex;
    }

    let counter = await config.flightSuretyData.airlineCounter.call();

    assert.equal(counter, 5, 'Airline count does not match')

    try {
      await config.flightSuretyData.removeAirline(airline2)
      await config.flightSuretyData.removeAirline(airline3)
      await config.flightSuretyData.removeAirline(airline4)
      await config.flightSuretyData.removeAirline(airline5)
    } catch (ex) {
      throw ex.message;
    }

    let updatedCount = await config.flightSuretyData.airlineCounter.call();

    assert.equal(updatedCount, 1, 'Airline count does not match')

  })

  it('(airlines) Registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines', async() => {
    let airline1 = accounts[0];
    let airline2 = accounts[1];
    let airline3 = accounts[2];
    let airline4 = accounts[3];
    let airline5 = accounts[4];
    let airline6 = accounts[5];
    let airline7 = accounts[6];

    const payment = web3.utils.toWei('10', 'ether');

    try {

      // await config.flightSuretyData.fundAirline(airline1, { value: payment });
      
      await config.flightSuretyApp.registerAirline(airline2)
      await config.flightSuretyData.fundAirline(airline2, { value: payment });
      
      await config.flightSuretyApp.registerAirline(airline3, { from: airline2 })
      await config.flightSuretyApp.registerAirline(airline4, { from: airline2 })
      await config.flightSuretyApp.registerAirline(airline5, { from: airline2 })
      await config.flightSuretyData.fundAirline(airline3, { value: payment });
      await config.flightSuretyData.fundAirline(airline4, { value: payment });
      await config.flightSuretyData.fundAirline(airline5, { value: payment });


      await config.flightSuretyApp.registerAirline(airline6, { from: airline2 })
      await config.flightSuretyApp.registerAirline(airline6, { from: airline3 })
      await config.flightSuretyApp.registerAirline(airline6, { from: airline4 })
      await config.flightSuretyApp.registerAirline(airline7, { from: airline2 })
      await config.flightSuretyApp.registerAirline(airline7, { from: airline3 })
      await config.flightSuretyApp.registerAirline(airline7, { from: airline4 })
      await config.flightSuretyApp.registerAirline(airline7, { from: airline5 })

    } catch(ex) {
      throw ex;
    }

    let counter = await config.flightSuretyData.airlineCounter.call();

    assert.equal(counter, 7, 'Multi-party consensus of 50% not reached')
  })

  it("(airline) can only participate in contract if it is funded", async () => {
    // ARRANGE
    let newAirline = accounts[10];

    // ACT
    try {
      await config.flightSuretyApp.registerAirline(newAirline);
    } catch (e) {}
    let result = await config.flightSuretyData.isFundedAirline.call(newAirline);

    // ASSERT
    assert.equal(
      result,
      false,
      "Airline should not be able to register another airline if it hasn't provided funding"
    );
  });
});
