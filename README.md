## BETOKEN:
### THE DECENTRALIZED TOKEN HEDGE FUND

Betoken is a decentralized hedge fund that uses its own internal prediction market to invest in ERC20 tokens.

Check out our public alpha: <a href="https://gateway.ipfs.io/ipns/QmR48YwyTwQBeEwCJQLa6CzGANjm2rt75rhGr1TYK7AuHw/">Click me</a>

 <hr>

## Overview:
Betoken consists of roughly 4 parts:


1) The actual <b>Betoken</b> smart contract, which holds all the funds for each group.


2) The <b>Oraclize</b> smart contract, which allows Betoken to access current token prices from an external source.


3) The <b>EtherDelta</b> smart contract, which allows Betoken to make trades on a decentralized platform.


4) The <b>Control Token</b> contract, an internal token unique to each group fund. Control Tokens dictate what proportion of the total pool each participant can invest, and also provide holders with commissions proportional to their holdings.

![Betoken Diagram](https://i.imgur.com/zvuHS9r.png)

<hr>

## Using Betoken:
Anyone can call the Betoken smart contract to create a new group fund. Each group fund goes through investment cycles, which are split into 5 stages: <b>ChangeMaking</b>, <b>ProposalMaking</b>, <b>Waiting</b>, <b>Ended</b>, and <b>Finalized</b>.

<b>ChangeMaking</b> is when new participants can be added, and it is also when new withdrawals and deposits can be made.

<b>ProposalMaking</b> is when participants indicate which tokens they wish to invest in and how much. Participants who wish to invest a certain amount also stake a proportional amount of ControlTokens.

<b>Waiting</b> is the investment period, where the tokens are bought and held.

<b>Ended</b> is when the tokens are sold.

<b>Finalized</b> is when ControlTokens are resdistributed depending on whether or not the investment proved to be profitable. The group's pool is then updated.

After each investment cycle, a new ChangeMaking period begins.

Control Tokens can be traded at any time, and the commissions attached provide additional incentive for investors to make good trades.
