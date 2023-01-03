# Spigot Migrations

Migrations contracts to deploy a Line of Credit with accompanying Spigot to existing protocols.

## Development

We use foundry for development and testing. Follow [installation guide](https://github.com/foundry-rs/foundry) on their repo.

The `Line-of-Credit` repo and contracts are included as a submodule, however the `Chainlink` and `Openzeppelin` libs are submodules of the `Line-of-Credit`, so they need to be installed.

This is reflected in the `remappings.txt`.

So, first run `forge install`, then `forge update`.

Next, create a `.env` file and add the `ETH_RPC_URL` for the archive node ( to enable forking ).

```
cp .env.sample .env
```

Update submodules:

```
git submodule update --recursive --remote
```

## Testing

We need to test against a fork of ethereum mainnet in order to interact with the deployed Idle Finance contracts.

```
source .env && forge test --fork-url $ETH_RPC_URL --fork-block-number 15795856 -vvvv
```
