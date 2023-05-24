NB_NODES_A := 2
NB_NODES_B := 2

B_MIN := $(shell echo $$(( $(NB_NODES_A) + 1 )))
B_MAX := $(shell echo $$(( $(NB_NODES_A) + $(NB_NODES_B) )))

NODES_A := $(addsuffix .done,$(addprefix genfiles/nodeA_,$(shell seq 1 ${NB_NODES_A})))
NODES_B := $(addsuffix .done,$(addprefix genfiles/nodeB_,$(shell seq ${B_MIN} ${B_MAX})))
DOCKER := docker run --platform linux/x86_64 --user $$(id -u) --rm
TM_A := tendermint/tendermint:v0.34.24
TM_B := tendermint/tendermint:v0.35.8
BIN_A := a-bins
BIN_B := b-bins
OUTPUT_DIR = ${PWD}/genfiles
TM_A_ROOT := ${OUTPUT_DIR}/nodeA
TM_B_ROOT := ${OUTPUT_DIR}/nodeB
VALIDATOR_COMMAND = jq '{ address: .address, pub_key: .pub_key }' "${ROOT}_$*/tendermint/config/priv_validator_key.json" | jq ".name = \"tendermint-$*\" | .power = \"1000\"" > $@

SHELL := bash

# Initialize Tendermint configuration and keys
# Copy the ledger staging file
define TM_INIT =
	mkdir -p "${ROOT}_$*/tendermint"
	mkdir -p "${ROOT}_$*/persistent-abci"
	mkdir -p "${ROOT}_$*/persistent-ledger"
	$(DOCKER) -v ${ROOT}_$*/tendermint:/tendermint ${TM} init validator
	$(DOCKER) -v ${ROOT}_$*/:/export alpine/openssl genpkey -algorithm Ed25519 -out /export/ledger.pem
	$(DOCKER) -v ${ROOT}_$*/:/export alpine/openssl genpkey -algorithm Ed25519 -out /export/abci.pem
	cp ledger_state.json5 ${ROOT}_$*/
	if [ -f "$(CURDIR)/${BIN}/migrations.json" ]; then \
		cp "${BIN}/migrations.json" ${ROOT}_$*/; \
	fi
endef

# Retrieve the Tendermint node ID
define TM_NODE_ID =
	id=$$($(DOCKER) -v ${ROOT}_$*/tendermint:/tendermint ${TM} show-node-id) ;\
	echo "$${id}@tendermint-$*:26656" > $@
endef

# Generate and copy the final genesis file
define TM_GENESIS =
	jq --slurpfile v ${OUTPUT_DIR}/node.validators '.validators = $$v | .chain_id = "many-e2e-dev" | .genesis_time = "2022-12-19T00:00:00.000000000Z"' "${ROOT}_$*/tendermint/config/genesis.json" > ${OUTPUT_DIR}/genesis_node${NODE_TYPE}_$*.json
	cp ${OUTPUT_DIR}/genesis_node${NODE_TYPE}_$*.json ${ROOT}_$*/tendermint/config/genesis.json
endef

# Build the ledger and ABCI docker images
define DOCKER_BUILD =
	mkdir -p ${OUTPUT_DIR}
	docker build . --platform linux/x86_64 -f dockerfiles/Dockerfile.many-abci-${NODE_TYPE} -t hybrid/many-abci-${NODE_TYPE}
	docker build . --platform linux/x86_64 -f dockerfiles/Dockerfile.many-ledger-${NODE_TYPE} -t hybrid/many-ledger-${NODE_TYPE}
	touch $@
endef

# WARN: The `all_tx_types` test will fail with mempool cache size set to "0"
define UPDATE_CONFIG =
	if [[ "${TM}" == *"v0.34"* ]]; then \
		$(UPDATE_CMD) '' proxy_app "\"tcp:\/\/abci-$*:26658\/\""; \
		$(UPDATE_CMD) '' moniker "\"many-tendermint-$*\""; \
		$(UPDATE_CMD) consensus timeout_commit "\"2s\""; \
		$(UPDATE_CMD) consensus timeout_precommit "\"2s\""; \
		$(UPDATE_CMD) p2p persistent_peers "\"$$(cat ${OUTPUT_DIR}/node_$*.config)\""; \
		$(UPDATE_CMD) p2p max_packet_msg_payload_size "1400"; \
		$(UPDATE_CMD) p2p pex "false"; \
	elif [[ "${TM}" == *"v0.35"* ]]; then \
		$(UPDATE_CMD) '' proxy-app "\"tcp:\/\/abci-$*:26658\/\""; \
		$(UPDATE_CMD) '' moniker "\"many-tendermint-$*\""; \
		$(UPDATE_CMD) consensus timeout-commit "\"2s\""; \
		$(UPDATE_CMD) consensus timeout-precommit "\"2s\""; \
		$(UPDATE_CMD) p2p persistent-peers "\"$$(cat ${OUTPUT_DIR}/node_$*.config)\""; \
		$(UPDATE_CMD) p2p pex "false"; \
	else \
		@echo "Unsupported Tendermint version." ; false ; \
	fi
	$(TM_GENESIS)
	touch $@
endef

.PHONY: clean
clean:
	if [ -f "$(CURDIR)/genfiles/docker-compose.json" ]; then \
		make stop-nodes; \
	fi
	rm -rf genfiles

genfiles/buildA: NODE_TYPE := a
genfiles/buildA:
	$(DOCKER_BUILD)

genfiles/buildB: NODE_TYPE := b
genfiles/buildB:
	$(DOCKER_BUILD)

# Extract node A validator
genfiles/nodeA_%.validator: ROOT := ${TM_A_ROOT}
genfiles/nodeA_%.validator: genfiles/nodeA_%.init
	$(VALIDATOR_COMMAND)

# Initialize node A configuration, persitent storage and keys
genfiles/nodeA_%.init: ROOT := ${TM_A_ROOT}
genfiles/nodeA_%.init: TM := ${TM_A}
genfiles/nodeA_%.init: BIN := ${BIN_A}
genfiles/nodeA_%.init:
	$(TM_INIT)

# Retrieve node A ID
genfiles/nodeA_%.nodeid: ROOT := ${TM_A_ROOT}
genfiles/nodeA_%.nodeid: TM := ${TM_A}
genfiles/nodeA_%.nodeid: genfiles/nodeA_%.init
	$(TM_NODE_ID)

# Generate node A configuration and genesis files
$(NODES_A): ROOT := ${TM_A_ROOT}
$(NODES_A): TM := ${TM_A}
$(NODES_A): NODE_TYPE := A
$(NODES_A): UPDATE_CMD = ${PWD}/update_toml_key.sh ${ROOT}_$*/tendermint/config/config.toml
$(NODES_A): genfiles/nodeA_%.done: genfiles/node.validators genfiles/node_%.config
	$(UPDATE_CONFIG)

# Concatenate all node IDs but self
# The value from this target will be used to set the `p2p persistent peers` configuration file entry
genfiles/node_%.config: $(NODES_A:%done=%nodeid) $(NODES_B:%done=%nodeid)
	shopt -s extglob; \
	eval 'paste -d "," ${OUTPUT_DIR}/node*_!($*).nodeid > $@'

# Concatenate all node validators
genfiles/node.validators: $(NODES_A:%done=%validator) $(NODES_B:%done=%validator)
	cat ${OUTPUT_DIR}/*.validator | jq -c > ${OUTPUT_DIR}/node.validators

# Extract node B validator
genfiles/nodeB_%.validator: ROOT := ${TM_B_ROOT}
genfiles/nodeB_%.validator: genfiles/nodeB_%.init
	$(VALIDATOR_COMMAND)

# Initialize node B configuration, persitent storage and keys
genfiles/nodeB_%.init: ROOT := ${TM_B_ROOT}
genfiles/nodeB_%.init: TM := ${TM_B}
genfiles/nodeB_%.init: BIN := ${BIN_B}
genfiles/nodeB_%.init:
	$(TM_INIT)

# Retrieve node B ID
genfiles/nodeB_%.nodeid: ROOT := ${TM_B_ROOT}
genfiles/nodeB_%.nodeid: TM := ${TM_B}
genfiles/nodeB_%.nodeid: genfiles/nodeB_%.init
	$(TM_NODE_ID)

# Generate node B configuration and genesis files
$(NODES_B): ROOT := ${TM_B_ROOT}
$(NODES_B): TM := ${TM_B}
$(NODES_B): NODE_TYPE := B
$(NODES_B): UPDATE_CMD = ${PWD}/update_toml_key.sh ${ROOT}_$*/tendermint/config/config.toml
$(NODES_B): genfiles/nodeB_%.done: genfiles/node.validators genfiles/node_%.config
	$(UPDATE_CONFIG)

# Generate the docker compose file
genfiles/docker_compose.json: $(NODES_A) $(NODES_B)
	docker pull bitnami/jsonnet
	docker run --user $$(id -u):$$(id -g) --rm -v "${PWD}:/volume:ro" -v "${OUTPUT_DIR}:/genfiles" bitnami/jsonnet \
		/volume/docker-compose.jsonnet \
		--tla-code NB_NODES_A=$(NB_NODES_A) \
		--tla-code NB_NODES_B=$(NB_NODES_B) \
		--tla-code tendermint_A_tag="\"$(TM_A)\"" \
		--tla-code tendermint_B_tag="\"$(TM_B)\"" \
		--tla-code enable_migrations_A="$(shell test -f $(BIN_A)/migrations.json && echo true || echo false)" \
		--tla-code enable_migrations_B="$(shell test -f $(BIN_B)/migrations.json && echo true || echo false)" \
		--tla-code user=$$(id -u) \
		-o /$@

.PHONY: start-nodes
start-nodes: genfiles/buildA genfiles/buildB genfiles/docker_compose.json
	docker-compose -f ${OUTPUT_DIR}/docker_compose.json -p e2e-ledger up

.PHONY: start-nodes-background
start-nodes-background: genfiles/buildA genfiles/buildB genfiles/docker_compose.json
	docker-compose -f ${OUTPUT_DIR}/docker_compose.json -p e2e-ledger up --detach

.PHONY: stop-nodes
stop-nodes:
	docker-compose -f ${OUTPUT_DIR}/docker_compose.json -p e2e-ledger stop

.PHONY: stop-single-node
stop-single-node:
	docker-compose -f ${OUTPUT_DIR}/docker_compose.json -p e2e-ledger stop tendermint-$(NODE)
	docker-compose -f ${OUTPUT_DIR}/docker_compose.json -p e2e-ledger stop abci-$(NODE)
	docker-compose -f ${OUTPUT_DIR}/docker_compose.json -p e2e-ledger stop ledger-$(NODE)

.PHONY: start-single-node-background
start-single-node-background: genfiles/buildA genfiles/buildB genfiles/docker_compose.json
	docker-compose -f ${OUTPUT_DIR}/docker_compose.json -p e2e-ledger up --detach tendermint-$(NODE)
	docker-compose -f ${OUTPUT_DIR}/docker_compose.json -p e2e-ledger up --detach abci-$(NODE)
	docker-compose -f ${OUTPUT_DIR}/docker_compose.json -p e2e-ledger up --detach ledger-$(NODE)
