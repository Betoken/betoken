const HDWalletProvider = require("@truffle/hdwallet-provider");
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
    mainnet: {
      provider: function() {
        const mnemonic = require("./secret.json");
        return new HDWalletProvider(mnemonic, "https://mainnet.infura.io/v3/2f4ac5ce683c4da09f88b2b564d44199", 1)
      },
      gas: 1000000,
      gasPrice: 2e9,
      network_id: 1
    },
    rinkeby: {
      provider: function() {
        const mnemonic = require("./secret.json");
        return new HDWalletProvider(mnemonic, "https://rinkeby.infura.io/v3/2f4ac5ce683c4da09f88b2b564d44199")
      },
      gas: 8000000,
      gasPrice: 4 * Math.pow(10, 9),
      network_id: 4
    }
  },
  compilers: {
    solc: {
      version: "0.5.12",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200   // Optimize for how many times you intend to run the code
        }
      }
    }
  },
  plugins: [ 'truffle-plugin-verify' ],
  api_keys: {
    etherscan: "9P9PSS55YN16E2BW6AV1U9CXE9KYCFUK7N"
  }
};