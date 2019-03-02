BetokenFund = artifacts.require "BetokenFund"
managers_to_onboard = require "./managers_to_onboard.json"
BETOKEN_ADDR = "0x5910d5abd4d5fd58b39957664cd9735cbfe42bf0"

module.exports = (callback) ->
    Betoken = await BetokenFund.at(BETOKEN_ADDR)
    i = 1
    for manager in managers_to_onboard
        console.log(manager.address + " onboarding... #{i}/#{managers_to_onboard.length}")
        i += 1
        await Betoken.airdropKairo([manager.address], manager.kro)
    return