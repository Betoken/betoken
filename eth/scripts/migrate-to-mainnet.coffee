MiniMeToken = artifacts.require "MiniMeToken"
managers_to_onboard = require "./migrate-managers.json"
KRO_ADDR = "0xE5fEf62fEFc4555560088B389E5f4Df2D45df4b1"

module.exports = (callback) ->
    Kairo = await MiniMeToken.at(KRO_ADDR)
    i = 1
    for manager in managers_to_onboard
        console.log(manager.address + " onboarding... #{i}/#{managers_to_onboard.length}")
        i += 1
        try
            await Kairo.generateTokens(manager.address, manager.kro)
        catch e
            console.log e.toString()
    callback()
    return