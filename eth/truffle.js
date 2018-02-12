module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      gas: 6000000,
      gasPrice: Math.pow(10, 8),
      network_id: "*" // match any network
    },
    rinkeby: {
      host: "localhost",
      port: 8545,
      gas: 5100000,
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
