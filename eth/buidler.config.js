usePlugin("@nomiclabs/buidler-truffle5");

module.exports = {
  solc: {
    version: "0.5.12",
    optimizer: {
      enabled: true,
      runs: 200
    }
  }
};