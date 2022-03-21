require("@nomiclabs/hardhat-waffle");
//require('dotenv').config();
const dotenv = require("dotenv");
dotenv.config({path: __dirname + '/.env'});

// The next lines import Hardhat task definitions, which can be used
//   for testing the frontend
require("./tasks/faucet");
require("./tasks/accounts");

// If using MetaMask, be sure to change the chainId to 1337
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.6.0"
      },
      {
        version: "0.6.6"
      },
      {
        version: "0.6.12"
      },
      {
        version: "0.8.0"
      }
    ]
  },
  networks: {
    //hardhat: {
    //  chainId: 31337
    //},
    kovan: {
      url: process.env.ALCHEMY_API_URL,
      accounts: [process.env.PRIVATE_KEY]
    }
  },
};
