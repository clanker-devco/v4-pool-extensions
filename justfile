default:
  @just --list

# run tests
test:
    #!/usr/bin/env bash
    set -euo pipefail
    # Load environment variables
    set -a
    source .env
    set +a

    # Run tests
    forge test