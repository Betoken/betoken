BetokenFund = artifacts.require("BetokenFund")
ControlToken = artifacts.require("ControlToken")
OraclizeHandler = artifacts.require("OraclizeHandler")

config = require "../deployment_configs/testnet.json"

dev_fee_address = "0xeabffa328d2e2340384ddfc128a78dd7964c6edb"

module.exports = (callback) ->
  old_contract = null
  new_contract = null

  #Get old BetokenFund
  BetokenFund.deployed().then(
    (_instance) -> old_contract = _instance
  ).then(
    #Uncommemt on Testnet or Mainnet (anywhere with an EtherDelta contract)
    () -> #old_contract.pause()
  ).then(
    () ->
      #Deploy new BetokenFund
      BetokenFund.new(
        config.etherDeltaAddress, #Ethdelta address
        dev_fee_address, #developerFeeAccount
        config.precision, #precision
        config.timeOfChangeMaking,#2 * 24 * 3600, #timeOfChangeMaking
        config.timeOfProposalMaking,#2 * 24 * 3600, #timeOfProposalMaking
        config.timeOfWaiting, #timeOfWaiting
        config.timeOfSellOrderWaiting, #timeOfSellOrderWaiting
        config.minStakeProportion, #minStakeProportion
        config.maxProposals, #maxProposals
        config.commissionRate, #commissionRate
        config.orderExpirationTimeInBlocks,#3600 / 20, #orderExpirationTimeInBlocks
        config.developerFeeProportion, #developerFeeProportion
        config.maxProposalsPerMember #maxProposalsPerMember
      ).then(
        (_instance) -> new_contract = _instance
      )
  ).then(
    () ->
      #Transfer participants data
      participants = []
      oraclizeAddr = null
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
        () -> new_contract.initializeParticipants(participants)
      ).then(
        #Initialize subcontracts for new BetokenFund
        () -> old_contract.controlTokenAddr()
      ).then(
        (_addr) -> kairoAddr = _addr
      ).then(
        () -> old_contract.oraclizeAddr()
      ).then(
        (_addr) -> oraclizeAddr = _addr
      ).then(
        () -> new_contract.initializeSubcontracts(kairoAddr, oraclizeAddr)
      )

      #Transfer ownership
      old_contract.changeOraclizeOwner(new_contract.address)
      old_contract.changeControlTokenOwner(new_contract.address)
  )
