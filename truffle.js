module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    ropsten: {
      host: "localhost",
      port: 8545,
      gasPrice: Math.pow(10, 8),
      gas: 5100000,
      network_id: "*" // match any network
    }
  }
};
