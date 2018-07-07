const HDWalletProvider = require("truffle-hdwallet-provider");
const mnemonic = "below renew bottom into dawn casino pull fox hawk pink crush cry";
module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      gas: 8000000,
      gasPrice: Math.pow(10, 8),
      network_id: "*" // match any network
    },
    rinkeby: {
      provider: function() {
          return new HDWalletProvider(mnemonic, "https://rinkeby.infura.io/m7Pdc77PjIwgmp7t0iKI")
      },
      host: "localhost",
      port: 8545,
      gas: 6000000,
      gasPrice: 20 * Math.pow(10, 9),
      network_id: 4
    }
  },
  solc: {
      optimizer: {
          enabled: true,
          runs: 200
      }
  }
};