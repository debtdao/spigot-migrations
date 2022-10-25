# Spigot Migrations

Migrations contracts to deploy a Line of Credit with accompanying Spigot to existing protocols.

## Development

We use foundry for development and testing. Follow [installation guide](https://github.com/foundry-rs/foundry) on their repo.

The `Line-of-Credit` repo and contracts are included as a submodule, however the `Chainlink` and `Openzeppelin` libs are submodules of the `Line-of-Credit`, so they need to be installed.

So, first run `forge install`, then

`cd lib/Line-of-Credit && forge install`

This is reflected in the `remappings.txt`.

## Structure

```
root
    |_script
        |_<protocol>
            |_deploy-<protocol>.s.sol
    |_src
        |_<protocol>
            |_Migration.sol
    |_test
        |_<protocol>
            |_<protocol>-migration.t.sol
```
