// Hardhat will run every *.js file in `test/`
// Hardhat tests are normally written with Mocha and Chai.
// Import Chai to use its asserting functions here.
const { expect } = require("chai");
const { ethers } = require("hardhat");  // make it explicit
const { Signer } = require("ethers");

const dotenv = require("dotenv");
dotenv.config({path: __dirname + '/.env'});

// `describe` is a Mocha function that allows you to organize your tests. It's
// not actually needed, but having your tests organized makes debugging them
// easier. All Mocha functions are available in the global scope.

// `describe` receives the name of a section of your test suite, and a callback.
// The callback must define the tests of that section. This callback can't be
// an async function.
describe("LendingService contract", function () {
  // Mocha has four functions that let you hook into the the test runner's
  // lifecycle. These are: `before`, `beforeEach`, `after`, `afterEach`.

  // They're very useful to setup the environment for tests, and to clean it
  // up after they run.

  // A common pattern is to declare some variables, and assign them in the
  // `before` and `beforeEach` callbacks.

  let LendingService;
  let hardhatService;
  let owner;
  let addr1;
  
  const ETHaddress = ethers.utils.getAddress("0x4281eCF07378Ee595C564a59048801330f3084eE");   // Kovan
  const aWETHaddress = ethers.utils.getAddress("0x87b1f4cf9BD63f7BBD3eE1aD04E8F52540349347");     // Kovan
  const LINKaddress = ethers.utils.getAddress("0xa36085F69e2889c224210F603D836748e7dC0088");  // Kovan
  const aLINKaddr = ethers.utils.getAddress("0xF345129E9AE2a94Ad59E11074dd7F624EFad103D");        // Kovan
  const SNXaddress = ethers.utils.getAddress("0x7FDb81B0b8a010dd4FFc57C3fecbf145BA8Bd947");   // Kovan
  const aSNXaddress = ethers.utils.getAddress("0xAA74AdA92dE4AbC0371b75eeA7b1bd790a69C9e1");      // Kovan
  const DAIaddress = ethers.utils.getAddress("0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD");   // Kovan

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    LendingService = await ethers.getContractFactory("LendingService");
    [owner, addr1] = await ethers.getSigners();

    // To deploy our contract, we just have to call LendingService.deploy() and await
    // for it to be deployed(), which happens onces its transaction has been mined.  
    const serviceProvider = ethers.utils.getAddress("0x88757f2f99175387aB4C6a4b3067c77A695b0349");
    hardhatService = await LendingService.deploy(SNXaddress, DAIaddress, serviceProvider);

    // We can interact with the contract by calling `hardhatService.method()`
    // await hardhatService.connect(addr1).<function_name>  // this is to execute contract's method from another account, addr1 here
    await hardhatService.deployed();
  });


  // We can nest describe calls to create subsections.
  describe("After calling contructor", function () {
    // `it` is another Mocha function. This is the one we use to define our
    // tests. It receives the test name, and a callback function.
    
    // If the callback function is async, Mocha will `await` it.
    it("Should get the correct lending pool address (on Kovan)", async function () {
      // Expect receives a value, and wraps it in an assertion objet. These
      // objects have a lot of utility methods to assert values.

      const lendingPoolAddr = ethers.utils.getAddress("0xE0fBa4Fc209b4948668006B2bE61711b7f465bAe");
      expect(await hardhatService.getAaveLendingPoolAddr()).to.equal(lendingPoolAddr);
    });

    it("Should get the correct aToken address (on Kovan)", async function () {
      expect(await hardhatService.getATokenAddress()).to.equal(aSNXaddress);
    });

    ///===== Something is wrong with ethers.getSigners() on Kovan testnet; Not working now
    it("Should return true as a signer", async function () {
      [owner] = await ethers.getSigners();
      expect(Signer.isSigner(owner).to.equal(true));
    });
  });


  describe("Transactions", function () {
    it("Should update deposited amount balances after deposit", async function () {
      ///===== Something is wrong with functions running on Kovan testnet today; Not working now
      await hardhatService.deposit(ETHaddress, ethers.utils.parseUnits("0.1", "ether"), addr1, 0, {
        gasLimit: 800000
      }); 
      expect(hardhatService.getDepositedBalance(addr1).to.equal(0.1));
    });
  }); 
});
