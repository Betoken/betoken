module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      gas: 7000000,
      gasPrice: Math.pow(10, 8),
      network_id: "*" // match any network
    },
    rinkeby: {
      host: "localhost",
      port: 8545,
      gas: 6910000,
      gasPrice: 20 * Math.pow(10, 9),
      network_id: 4
    }
  }
};
