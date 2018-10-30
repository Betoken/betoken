MiniMeToken = artifacts.require "MiniMeToken"
inactive_managers = require "./inactive_managers.json"
KAIRO_ADDR = "0xDeB05FE4905EE7662b1230e7c1f29F386E598E66"
Kairo = MiniMeToken.at(KAIRO_ADDR)

module.exports = (callback) ->
    i = 1
    for manager in inactive_managers
        console.log(manager.address + " deleting... #{i}/#{inactive_managers.length}")
        i += 1
        await Kairo.balanceOf.call(manager.address).then(
            (balance) ->
                Kairo.destroyTokens(manager.address, balance)
        )
    return
