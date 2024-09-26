GIT_ROOT="$BATS_TEST_DIRNAME/../../"
ACCOUNT="mqdukzwuwgt3porn6q4vq4xu3mwy5gyskhouryzbscq7wb2iaaaaac6"

load '../test_helper/load'

function setup() {
    mkdir "$BATS_TEST_ROOTDIR"
    cd "$GIT_ROOT" || exit

    (
      make clean
    ) > /dev/null
}

function teardown() {
    (
      cd "$GIT_ROOT" || exit
      make stop-nodes
    ) 2> /dev/null
    cd "$GIT_ROOT/bats/tests" || exit 1
}

function check_ledger_commands() {
    # Ledger send
    ledger_a "$(pem 1)" 8001 send "$(identity 2)" 1000 MFX
    check_consistency_a "$(identity 1)" 999999000 8001 8002
    check_consistency_b "$(identity 1)" 999999000 8003
    check_consistency_a "$(identity 2)" 1000 8001 8002
    check_consistency_b "$(identity 2)" 1000 8003
}

function check_multisig() {
    # Multisig submit
    ledger_a "$(pem 1)" 8001 multisig submit ${ACCOUNT} --execute-automatically true send "$(identity 2)" 2000 MFX
    token=$(echo "${output}" | grep -o 'Transaction Token: .*' | cut -d ' ' -f 3)
    check_consistency_a "${ACCOUNT}" 50000 8001 8002
    check_consistency_b "${ACCOUNT}" 50000 8003
    check_consistency_a "$(identity 2)" 1000 8001 8002
    check_consistency_b "$(identity 2)" 1000 8003

    # Multisig approve and execute automatically
    ledger_a "$(pem 2)" 8001 multisig approve "${token}"
    check_consistency_a "${ACCOUNT}" 48000 8001 8002
    check_consistency_b "${ACCOUNT}" 48000 8003
    check_consistency_a "$(identity 2)" 3000 8001 8002
    check_consistency_b "$(identity 2)" 3000 8003

    # Multisig submit
    ledger_a "$(pem 1)" 8001 multisig submit ${ACCOUNT} send "$(identity 2)" 2000 MFX
    token=$(echo "${output}" | grep -o 'Transaction Token: .*' | cut -d ' ' -f 3)
    check_consistency_a "${ACCOUNT}" 48000 8001 8002
    check_consistency_b "${ACCOUNT}" 48000 8003
    check_consistency_a "$(identity 2)" 3000 8001 8002
    check_consistency_b "$(identity 2)" 3000 8003

    # Multisig revoke
    ledger_a "$(pem 1)" 8001 multisig revoke "${token}"
    check_consistency_a "${ACCOUNT}" 48000 8001 8002
    check_consistency_b "${ACCOUNT}" 48000 8003
    check_consistency_a "$(identity 2)" 3000 8001 8002
    check_consistency_b "$(identity 2)" 3000 8003

    # Multisig withdraw
    # TODO: Add withdraw to ledger
#    ledger_a "$(pem 1)" 8001 multisig withdraw "${token}"
#    check_consistency_a "${ACCOUNT}" 48000 8001 8002
#    check_consistency_b "${ACCOUNT}" 48000 8003
#    check_consistency_a "$(identity 2)" 3000 8001 8002
#    check_consistency_b "$(identity 2)" 3000 8003

    # Multisig change ACCOUNT default
    ledger_a "$(pem 1)" 8001 multisig set-defaults "${ACCOUNT}" --timeout 10s
    check_consistency_a "${ACCOUNT}" 48000 8001 8002
    check_consistency_b "${ACCOUNT}" 48000 8003
    check_consistency_a "$(identity 2)" 3000 8001 8002
    check_consistency_b "$(identity 2)" 3000 8003

    # Multisig submit (new defaults)
    ledger_a "$(pem 1)" 8001 multisig submit ${ACCOUNT} send "$(identity 2)" 2000 MFX
    token=$(echo "${output}" | grep -o 'Transaction Token: .*' | cut -d ' ' -f 3)
    check_consistency_a "${ACCOUNT}" 48000 8001 8002
    check_consistency_b "${ACCOUNT}" 48000 8003
    check_consistency_a "$(identity 2)" 3000 8001 8002
    check_consistency_b "$(identity 2)" 3000 8003

    # Trigger multisig timeout
    sleep 20

    # Check the multisig transaction has expired
    ledger_a "$(pem 1)" 8001 multisig info "${token}"
    assert_output --partial "state: Expired"
}

# TODO: Use `ledger_*` when account support is added to `ledger`
function check_account() {
    local account

    # Create
    many_a "$(pem 1)" 8001 account.create '{0: "Foobar", 1: {"'$(identity 2)'": ["canLedgerTransact"]}, 2: [0]}'
    account=$(echo "${output}" | grep -oP "h'\K\w+" | xargs "$GIT_ROOT/a-bins/many" id)
    many_a "$(pem 1)" 8001 account.info '{0: "'${account}'"}'
    assert_output --partial "Foobar"
    many_b "$(pem 1)" 8003 account.info '{0: "'${account}'"}'
    assert_output --partial "Foobar"

    # Set description
    many_a "$(pem 1)" 8001 account.setDescription '{0: "'${account}'", 1: "Barfoo"}'
    many_a "$(pem 1)" 8001 account.info '{0: "'${account}'"}'
    assert_output --partial "Barfoo"
    many_b "$(pem 1)" 8003 account.info '{0: "'${account}'"}'
    assert_output --partial "Barfoo"

    # Add roles
    many_a "$(pem 1)" 8001 account.addRoles '{0: "'${account}'", 1: {"'$(identity 3)'": ["canLedgerTransact"]}}'
    many_a "$(pem 1)" 8001 account.info '{0: "'${account}'"}'
    assert_output --partial "$(identity_hex 3)"
    many_b "$(pem 1)" 8003 account.info '{0: "'${account}'"}'
    assert_output --partial "$(identity_hex 3)"

    # Add features
    many_a "$(pem 1)" 8001 account.addFeatures '{0: "'${account}'", 1: {"'$(identity 3)'": ["canMultisigApprove"]}, 2: [[1, {0: 2, 1: 15}]]}'
    many_a "$(pem 1)" 8001 account.info '{0: "'${account}'"}'
    assert_output --partial "canMultisigApprove"
    many_b "$(pem 1)" 8003 account.info '{0: "'${account}'"}'
    assert_output --partial "canMultisigApprove"

    # Remove roles
    many_a "$(pem 1)" 8001 account.removeRoles '{0: "'${account}'", 1: {"'$(identity 3)'": ["canMultisigApprove"]}}'
    many_a "$(pem 1)" 8001 account.info '{0: "'${account}'"}'
    refute_output --partial "canMultisigApprove"
    many_b "$(pem 1)" 8003 account.info '{0: "'${account}'"}'
    refute_output --partial "canMultisigApprove"

    # Disable
    many_a "$(pem 1)" 8001 account.disable '{0: "'${account}'"}'
    many_a "$(pem 1)" 8001 account.info '{0: "'${account}'"}'
    assert_output --partial "3: true"
    many_b "$(pem 1)" 8003 account.info '{0: "'${account}'"}'
    assert_output --partial "3: true"
}

function check_ledger_token() {
    local token

    # Create token
    ledger_a "$(pem 1)" 8001 token create Foobar FBR 9
    assert_output --partial "TokenCreateReturns"

    # TODO: Use the symbol ticker instead of the symbol address when support is added to `ledger`
    token=$(echo "${output}" | grep -Pzo '(?s)symbol:.*?\),' | sed -n '3p' | cut -d '"' -f 2)

    # Update token
    ledger_a "$(pem 1)" 8001 token update "$token" --ticker ABC --name "def" --memo "A memo"
    ledger_a "$(pem 1)" 8001 token info "$token"
    assert_output --partial "ABC"
    assert_output --partial "def"

    # Add ext. info
    ledger_a "$(pem 1)" 8001 token add-ext-info "$token" memo "Some memo"
    ledger_a "$(pem 1)" 8001 token info "$token"
    assert_output --partial "Some memo"

    # Remove ext.info
    ledger_a "$(pem 1)" 8001 token remove-ext-info "$token" 0
    refute_output --partial "Some memo"

    # Mint
    ledger_a "$(pem 1)" 8001 token mint "$token" '{"'"$(identity 2)"'": 123}'
    sleep 1
    ledger_a "$(pem 2)" 8001 balance
    assert_output --partial "123"

    # Burn
    ledger_a "$(pem 1)" 8001 token burn "$token" '{"'"$(identity 2)"'": 123}' --error-on-under-burn
    sleep 1
    ledger_a "$(pem 2)" 8001 balance
    refute_output --partial "123"
}

@test "$SUITE: Hybrid network supports all tx types. B can catch up." {
    for i in {1..3}; do
      make NB_NODES_A=2 NB_NODES_B=2 NODE="${i}" start-single-node-background || {
        echo Could not start nodes... >&3
        exit 1
      }
    done

    # Give time to the servers to start.
    sleep 30
    timeout 60s bash <<EOT
      while ! $GIT_ROOT/a-bins/many message --server http://localhost:8002 status; do
        sleep 1
      done >/dev/null
EOT

    wait_for_block_a 30 8001

    check_consistency_a "$(identity 1)" 1000000000 8001 8002
    check_consistency_b "$(identity 1)" 1000000000 8003

    check_ledger_commands
    check_account
    check_multisig

    make NB_NODES_A=2 NB_NODES_B=2 NODE="4" start-single-node-background || {
      echo Could not start nodes... >&3
      exit 1
    }
    timeout 30s bash <<EOT
    while ! $GIT_ROOT/b-bins/many message --server http://localhost:8004 status; do
      sleep 1
    done >/dev/null
EOT

    sleep 30

    check_consistency_a "$(identity 1)" 999999000 8001 8002
    check_consistency_b "$(identity 1)" 999999000 8003 8004
    check_consistency_a "${ACCOUNT}" 48000 8001 8002
    check_consistency_b "${ACCOUNT}" 48000 8003 8004
    check_consistency_a "$(identity 2)" 3000 8001 8002
    check_consistency_b "$(identity 2)" 3000 8003 8004
}

@test "$SUITE: Hybrid network support token tx types. B can catch up." {
    local a_block_height
    local a_disabled
    local b_block_height
    local b_disabled

    local block_height_query
    local disabled_query
    block_height_query=('.[] | map(select(.name == "Token Migration")) | .[].block_height')
    disabled_query=('.[] | map(select(.name == "Token Migration")) | .[].disabled')

    if [ -f "$GIT_ROOT/a-bins/ledger_migrations.json" ] && [ -f "$GIT_ROOT/b-bins/ledger_migrations.json" ]; then \
      a_block_height=$(jq "${block_height_query[@]}" "$GIT_ROOT/a-bins/ledger_migrations.json"); \
      b_block_height=$(jq "${block_height_query[@]}" "$GIT_ROOT/b-bins/ledger_migrations.json"); \
      a_disabled=$(jq "${disabled_query[@]}" "$GIT_ROOT/a-bins/ledger_migrations.json"); \
      b_disabled=$(jq "${disabled_query[@]}" "$GIT_ROOT/b-bins/ledger_migrations.json"); \

      if [ "$a_disabled" = "true" ] || [ "$b_disabled" = "true" ]; then \
        skip "Token migration is disabled"; \
      fi

      if [ "$a_block_height" != "$b_block_height" ]; then \
        skip "Token migration block height are not the same"; \
      fi
    else \
      skip "Migration files not found"; \
    fi

    for i in {1..3}; do
      make NB_NODES_A=2 NB_NODES_B=2 NODE="${i}" start-single-node-background || {
        echo Could not start nodes... >&3
        exit 1
      }
    done

    # Give time to the servers to start.
    sleep 30
    timeout 60s bash <<EOT
      while ! $GIT_ROOT/a-bins/many message --server http://localhost:8002 status; do
        sleep 1
      done >/dev/null
EOT

    # At this point, `a_block_height` == `b_block_height`
    wait_for_block_a "$a_block_height" 8001

    check_consistency_a "$(identity 1)" 1000000000 8001 8002
    check_consistency_b "$(identity 1)" 1000000000 8003

    check_ledger_commands
    check_account
    check_multisig
    check_ledger_token

    make NB_NODES_A=2 NB_NODES_B=2 NODE="4" start-single-node-background || {
      echo Could not start nodes... >&3
      exit 1
    }
    timeout 30s bash <<EOT
    while ! $GIT_ROOT/b-bins/many message --server http://localhost:8004 status; do
      sleep 1
    done >/dev/null
EOT

    sleep 30

    check_consistency_a "$(identity 1)" 999999000 8001 8002
    check_consistency_b "$(identity 1)" 999999000 8003 8004
    check_consistency_a "${ACCOUNT}" 48000 8001 8002
    check_consistency_b "${ACCOUNT}" 48000 8003 8004
    check_consistency_a "$(identity 2)" 3000 8001 8002
    check_consistency_b "$(identity 2)" 3000 8003 8004
}
