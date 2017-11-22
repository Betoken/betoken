module.exports = {
  // See <http://truffleframework.com/docs/advanced/configuration>
  // to customize your Truffle configuration!
  networks: {
    rinkeby: {
      host: "localhost",
      port: 8545,
      gas: 5500000,
      gasPrice: Math.pow(10, 8),
      network_id: "*" // match any network
    }
  }
};
