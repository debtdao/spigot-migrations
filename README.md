# Spigot Migrations

Migrations contracts to deploy a Line of Credit with accompanying Spigot to existing protocols.

## Development

We use foundry for development and testing. Follow [installation guide](https://github.com/foundry-rs/foundry) on their repo.

The `Line-of-Credit` repo and contracts are included as a submodule, however the `Chainlink` and `Openzeppelin` libs are submodules of the `Line-of-Credit`, so they need to be installed.

So, first run `forge install`, then

`cd lib/Line-of-Credit && forge install`

This is reflected in the `remappings.txt`.

## Testing

We need to test against a fork of ethereum mainnet in order to interact with the deployed Idle Finance contracts.

```
forge test -vvvv
```

## Structure

The migration for each protocol is split into three separate files. `script` for deployment, `src` for the contract itself, and `test` for the tests that rely on an archived RPC node for testing against a fork of mainnet.

```

```
