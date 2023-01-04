# Idle Finance Migration Guide

The files contained in this directory enable the deployment of a Secured Line of Credit for Idle Finance's Fee Collector.

All relevant contract address and parameters for the migration are located in the [settings.yaml](./settings.yml) file.

Detailed documentation of the migration process can be found in the [Idle Migration Guide](./GUIDE.md).

## Testing

Tests require the `ETH_RPC_URL` to be set with an RPC URL of a mainnet archival node as some tests require a fork of Ethereum's mainnet.

```
forge test --match-contract IdleMigrationTest -vv --gas-report
```

## Deployment

### Local Environment

// coming soon

### Mainnet

// coming soon