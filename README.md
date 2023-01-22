# Spigot Migrations

Migrations contracts to deploy a Line of Credit with accompanying Spigot to existing protocols.

## Development

We use foundry for development and testing. Follow [installation guide](https://github.com/foundry-rs/foundry) on their repo.

The `Line-of-Credit` repo and contracts are included as a submodule, however the `Chainlink` and `Openzeppelin` libs are submodules of the `Line-of-Credit`, so they need to be installed.

This is reflected in the `remappings.txt`.

So, first run `forge install`, then `forge update`.

Next, create a `.env` file and add the `ETH_RPC_URL` for the archive node ( to enable forking ) and deployment to mainnet.

```
cp .env.sample .env
```

Next, update submodules and ensure their on the correct branches.

```
git submodule update --recursive --remote
```

## Testing

Some tests require the `ETH_RPC_URL` to be set to a RPC URL on Ethereum mainnet.

```
forge test
```

## Migrations

All contracts, scripts, tests, and docs for each migration can be located in `migrations/<protocol_name>`.
