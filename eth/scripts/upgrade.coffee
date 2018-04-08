BetokenFund = artifacts.require("BetokenFund")
ControlToken = artifacts.require("ControlToken")
ShareToken = artifacts.require("ShareToken")

config = require "../deployment_configs/testnet.json"

dev_fee_address = "0xDbE011EB3fe8C77C94Cc9d9EC176BDddC937F425"
old_address = "0x8562D0E4E2853493E5d908Ec1caAa05604d48605"

module.exports = (callback) ->
  old_contract = BetokenFund.at(old_address)
  new_contract = null
  controlTokenAddr = null

  old_contract.controlTokenAddr().then(
    (_addr) ->
      controlTokenAddr = _addr
  ).then(
    () ->
      #Deploy new BetokenFund
      ShareToken.new().then(
        (_shareToken) ->
          console.log("Created new ShareToken at " + _shareToken.address)
          BetokenFund.new(
            controlTokenAddr,
            _shareToken.address,
            config.kyberAddress,
            dev_fee_address,
            config.phaseLengths,
            config.commissionRate,
            config.developerFeeProportion,
            config.functionCallReward,
            old_address
          ).then(
            (_instance) ->
              new_contract = _instance
              console.log("Created new BetokenFund at " + _instance.address)
          ).then(
            () ->
              _shareToken.transferOwnership(new_contract.address)
              console.log("Transferred ownership of " + _shareToken.address + " to " + new_contract.address)
          )
      )

  ).then(
    () ->
      #Transfer ownership
      old_contract.changeControlTokenOwner(new_contract.address)
      console.log("Transferred ownership of " + controlTokenAddr + " to " + new_contract.address)
  )
