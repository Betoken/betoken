const HDWalletProvider = require("truffle-hdwallet-provider");
module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      gas: 80000000,
      gasPrice: Math.pow(10, 8),
      network_id: "*" // match any network
    },
    mainnet: {
      provider: function() {
        const mnemonic = require("./secret.json");
        return new HDWalletProvider(mnemonic, "https://mainnet.infura.io/v3/3057a4979e92452bae6afaabed67a724")
      },
      host: "localhost",
      port: 8545,
      gas: 6000000,
      gasPrice: 8 * Math.pow(10, 9),
      network_id: 1
    },
    rinkeby: {
      provider: function() {
        const mnemonic = require("./secret.json");
        return new HDWalletProvider(mnemonic, "https://rinkeby.infura.io/v3/3057a4979e92452bae6afaabed67a724")
      },
      host: "localhost",
      port: 8545,
      gas: 6000000,
      gasPrice: 8 * Math.pow(10, 9),
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