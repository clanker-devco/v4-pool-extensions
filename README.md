# Clanker v4.1 Pool Extension Examples 

This repo contains examples of Clanker v4.1 pool extension contracts. Pool extensions are a feature enabling advanced users to add custom logic to a pool's after swap flow. See the [documentation](https://clanker.gitbook.io/clanker-documentation/references/core-contracts/v4/clankerhookv2/pool-extensions) for a high level explainer.

Note: pool extensions are not enabled by default. To enable a pool extension that you developed, please reach out to the Clanker team. We're happy to help!

## Extension Examples

Extensions ready for deployment and use:
- [UniV3SwapExtension](src/for-use/UniV3SwapExtension.sol): Uses generated fees to swap for a different token on a Uniswap v3 pool.
- [UniV4SwapExtension](src/for-use/UniV4SwapExtension.sol): Uses generated fees to swap for a different token on a Uniswap v4 pool.

Example "how-to" Pool Extensions, not intended for deployment:
- [AssertFeeConfigExample](src/how-to-examples/AssertFeeConfigExample.sol): Asserts that a token's fee config was setup a certain way. Including: the fee recipient is the pool extension, the fee admin is the dead address, the fee preference is in the paired token, and the fee BPS is a certain value.
- [PassedInDataExample](src/how-to-examples/PassedInDataExample.sol): Accesses passed in data in the setup and swap phases.
- [UserBalanceDeltaExample](src/how-to-examples/UserBalanceDeltaExample.sol): Records the amount of token spent and purchased by a swapper.

Empty extensions for user development:
- [CreateYourOwnExtension](src/CreateYourOwnExtension.sol): An empty extension that can be used as a template for new extensions.

## Repo Instructions

### Setup .env 

Copy the .env.example file to .env and fill out the missing RPC field. This repo is currently only setup to work on Base Mainnet.

```bash
cp .env.example .env
```

### Installing Dependencies

```bash
# note: we use the submodules inside of the clanker-v4 repo to simplify the dependencies
git submodule update --init --recursive
```

### Running Tests

```bash
# this loads the .env file and runs the tests
just test
```
If you get errors with missing files, check that the `/lib/clanker-v4/lib`'s submodules are properly installed (files should not be empty). If you need to re-install the submodules for whatever reason:
```
# Clean all submodule state
git submodule deinit --all --force
rm -rf .git/modules
git clean -fdx lib/

# Start fresh
git submodule update --init --recursive
```

### Deployments

*coming soon*
