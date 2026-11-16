#!/usr/bin/env bash
# Start script for the Apache Kafka Railway template (single-node KRaft).
set -euo pipefail

DATA_ROOT="${KAFKA_DATA_ROOT:-/var/lib/kafka}"   # the Railway volume
LOG_DIR="$DATA_ROOT/kraft-data"                   # subfolder: the volume root has lost+found
CONF=/opt/kafka/config/railway-server.properties
INTERNAL_PORT=9092
CONTROLLER_PORT=9093
LOCAL_PORT=9095        # loopback only: inter-broker and the start script's admin calls
EXTERNAL_PORT=9094
HEALTH_PORT="${PORT:-8080}"
SASL_USER="${KAFKA_SASL_USERNAME:-kafka}"
SASL_PASS="${KAFKA_SASL_PASSWORD:-}"
PRIVATE_HOST="${RAILWAY_PRIVATE_DOMAIN:-localhost}"
PUBLIC_HOST="${RAILWAY_TCP_PROXY_DOMAIN:-}"
PUBLIC_HOST="${PUBLIC_HOST%.}"   # Railway may report the proxy domain with a trailing dot
PUBLIC_PORT="${RAILWAY_TCP_PROXY_PORT:-}"

export KAFKA_HEAP_OPTS="${KAFKA_HEAP_OPTS:--Xms256m -Xmx1g}"

if [ -n "$PUBLIC_HOST" ] && [ -z "$SASL_PASS" ]; then
  echo "ERROR: a public TCP proxy is attached but KAFKA_SASL_PASSWORD is empty. Refusing to expose Kafka without a password." >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
rm -f /tmp/kafka-ready

# Cluster id: generated once, kept on the volume.
if [ ! -s "$DATA_ROOT/cluster-id" ]; then
  /opt/kafka/bin/kafka-storage.sh random-uuid > "$DATA_ROOT/cluster-id"
fi
CLUSTER_ID="$(cat "$DATA_ROOT/cluster-id")"

# The private domain doesn't resolve inside a deploy until it is live, so the broker talks
# to itself (and the admin calls below) over a loopback listener.
listeners="INTERNAL://:${INTERNAL_PORT},LOCAL://127.0.0.1:${LOCAL_PORT},CONTROLLER://localhost:${CONTROLLER_PORT}"
advertised="INTERNAL://${PRIVATE_HOST}:${INTERNAL_PORT},LOCAL://127.0.0.1:${LOCAL_PORT}"
protocols="INTERNAL:PLAINTEXT,LOCAL:PLAINTEXT,CONTROLLER:PLAINTEXT"
if [ -n "$PUBLIC_HOST" ] && [ -n "$PUBLIC_PORT" ]; then
  listeners="${listeners},EXTERNAL://:${EXTERNAL_PORT}"
  advertised="${advertised},EXTERNAL://${PUBLIC_HOST}:${PUBLIC_PORT}"
  protocols="${protocols},EXTERNAL:SASL_PLAINTEXT"
  echo "===> Public listener: ${PUBLIC_HOST}:${PUBLIC_PORT} (SASL SCRAM-SHA-256/512, user ${SASL_USER})"
else
  echo "===> No TCP proxy found: Kafka is reachable on the private network only"
fi
echo "===> Private listener: ${PRIVATE_HOST}:${INTERNAL_PORT} (plaintext)"

cat > "$CONF" <<PROPS
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@localhost:${CONTROLLER_PORT}
controller.listener.names=CONTROLLER
listeners=${listeners}
advertised.listeners=${advertised}
listener.security.protocol.map=${protocols}
inter.broker.listener.name=LOCAL
listener.name.external.sasl.enabled.mechanisms=SCRAM-SHA-256,SCRAM-SHA-512
listener.name.external.scram-sha-256.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required;
listener.name.external.scram-sha-512.sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required;
log.dirs=${LOG_DIR}
num.partitions=${KAFKA_NUM_PARTITIONS:-1}
default.replication.factor=1
min.insync.replicas=1
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
share.coordinator.state.topic.replication.factor=1
share.coordinator.state.topic.min.isr=1
group.initial.rebalance.delay.ms=0
auto.create.topics.enable=${KAFKA_AUTO_CREATE_TOPICS:-true}
log.retention.hours=${KAFKA_LOG_RETENTION_HOURS:-168}
PROPS

# Extra settings: KAFKA_CFG_LOG_RETENTION_BYTES=1073741824 -> log.retention.bytes=1073741824
while IFS='=' read -r name value; do
  case "$name" in
    KAFKA_CFG_*)
      key="$(echo "${name#KAFKA_CFG_}" | tr '[:upper:]' '[:lower:]' | tr '_' '.')"
      sed -i "/^${key//./\\.}=/d" "$CONF"
      echo "${key}=${value}" >> "$CONF"
      echo "===> Extra setting: ${key}"
      ;;
  esac
done < <(env)

/opt/kafka/bin/kafka-storage.sh format -t "$CLUSTER_ID" -c "$CONF" --ignore-formatted

# Health endpoint for Railway (HTTP on $PORT).
nc -lk -p "$HEALTH_PORT" -e /usr/local/bin/railway-kafka-health &

# Once the broker answers, create or update the SCRAM user, then mark ready.
(
  for _ in $(seq 1 120); do
    if /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server "127.0.0.1:${LOCAL_PORT}" >/dev/null 2>&1; then
      if [ -n "$SASL_PASS" ]; then
        ok=1
        for mech in SCRAM-SHA-256 SCRAM-SHA-512; do
          /opt/kafka/bin/kafka-configs.sh --bootstrap-server "127.0.0.1:${LOCAL_PORT}" --alter \
            --add-config "${mech}=[password=${SASL_PASS}]" \
            --entity-type users --entity-name "$SASL_USER" >/dev/null || ok=0
        done
        if [ "$ok" != 1 ]; then sleep 2; continue; fi
        echo "===> SASL user '${SASL_USER}' is set (SCRAM-SHA-256 and SCRAM-SHA-512)"
      fi
      touch /tmp/kafka-ready
      echo "===> Kafka is ready"
      exit 0
    fi
    sleep 2
  done
  echo "WARN: broker did not answer within 240 s" >&2
) &

exec /opt/kafka/bin/kafka-server-start.sh "$CONF"
