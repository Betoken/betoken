BetokenFund = artifacts.require("BetokenFund")
ControlToken = artifacts.require("ControlToken")

config = require "../deployment_configs/testnet.json"

dev_fee_address = "0xDbE011EB3fe8C77C94Cc9d9EC176BDddC937F425"
old_address = "0x8562D0E4E2853493E5d908Ec1caAa05604d48605"
start_cycle_number = 0

module.exports = (callback) ->
  old_contract = BetokenFund.at(old_address)
  new_contract = null
  controlTokenAddr = null
  shareTokenAddr = null

  old_contract.controlTokenAddr().then(
    (_addr) ->
      controlTokenAddr = _addr
  ).then(
    () ->
      old_contract.shareTokenAddr().then(
        (_addr) ->
          shareTokenAddr = _addr
      )
  ).then(
    () ->
      #Deploy new BetokenFund
      BetokenFund.new(
        controlTokenAddr,
        shareTokenAddr,
        config.kyberAddress,
        dev_fee_address,
        start_cycle_number,
        config.phaseLengths,
        config.commissionRate,
        config.developerFeeProportion,
        config.functionCallReward
      ).then(
        (_instance) ->
          new_contract = _instance
          console.log("Created new BetokenFund at " + _instance.address)
      )
  ).then(
    () ->
      #Transfer ownership
      old_contract.changeControlTokenOwner(new_contract.address)
      old_contract.changeShareTokenOwner(new_contract.address)
  )
