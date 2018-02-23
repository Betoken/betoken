BetokenFund = artifacts.require("BetokenFund")
ControlToken = artifacts.require("ControlToken")

config = require "../deployment_configs/testnet.json"

dev_fee_address = "0xDbE011EB3fe8C77C94Cc9d9EC176BDddC937F425"
old_address = "0x8562D0E4E2853493E5d908Ec1caAa05604d48605"
start_cycle_number = 0

module.exports = (callback) ->
  old_contract = BetokenFund.at(old_address)
  new_contract = null

  old_contract.pause().then(
    () ->
      #Deploy new BetokenFund
      BetokenFund.new(
        config.kyberAddress, #KyberNetwork address
        dev_fee_address, #developerFeeAccount
        config.timeOfChangeMaking,#2 * 24 * 3600, #timeOfChangeMaking
        config.timeOfProposalMaking,#2 * 24 * 3600, #timeOfProposalMaking
        config.timeOfWaiting, #timeOfWaiting
        config.minStakeProportion, #minStakeProportion
        config.maxProposals, #maxProposals
        config.commissionRate, #commissionRate
        config.developerFeeProportion, #developerFeeProportion
        config.maxProposalsPerMember, #maxProposalsPerMember
        start_cycle_number #cycleNumber
      ).then(
        (_instance) ->
          new_contract = _instance
          console.log("Created new BetokenFund at " + _instance.address)
      )
  ).then(
    () ->
      #Transfer participants data
      participants = []
      kairoAddr = null

      old_contract.participantsCount().then(
        (_count) ->
          count = _count.toNumber()
          if count == 0
            return
          participants = new Array(count)
          getItem = (id) ->
            return old_contract.participants(id).then(
              (_item) ->
                return new Promise((fullfill, reject) ->
                  if typeof _item != null
                    participants[id] = _item
                    fullfill()
                  else
                    reject()
                  return
                )
            )
          getAllItems = (getItem(id) for id in [0..count - 1])
          return Promise.all(getAllItems)
      ).then(
        () ->
          new_contract.initializeParticipants(participants)
          console.log "Initializing participant list..."
      ).then(
        #Initialize subcontracts for new BetokenFund
        () -> old_contract.controlTokenAddr()
      ).then(
        (_addr) -> kairoAddr = _addr
      ).then(
        () -> new_contract.initializeSubcontracts(kairoAddr)
      )

      #Transfer ownership
      old_contract.changeControlTokenOwner(new_contract.address)
  )
