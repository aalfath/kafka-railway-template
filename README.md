# Apache Kafka on Railway

A single-node [Apache Kafka](https://kafka.apache.org/) 4.4.0 broker for Railway, in KRaft mode (no ZooKeeper), built from the official `apache/kafka` image pinned by digest.

## What the template deploys

One service, **Kafka**:

- **Image:** `apache/kafka:4.4.0@sha256:833b867a9585a141da455dc2b57431c65cbccb27f11c91f694444cca9f777e0f`, wrapped by a small start script (`start.sh`).
- **Volume** at `/var/lib/kafka`: topic data (`kraft-data/`) and the cluster id. Data survives redeploys and restarts.
- **Private listener** `kafka.railway.internal:9092`, plaintext, for services in the same Railway project.
- **Public listener** through a Railway TCP proxy, SASL/SCRAM (SHA-256 or SHA-512) with a generated password. The broker refuses to start if a TCP proxy is attached and no password is set.
- **Health check** on `/` at `PORT` (8080): 200 once the broker answers and the SASL user is set.

## Variables

| Variable | Default | What it does |
|---|---|---|
| `KAFKA_SASL_USERNAME` | `kafka` | SASL user for the public listener |
| `KAFKA_SASL_PASSWORD` | generated (32 characters) | Its password. Changing it and redeploying updates the user |
| `PORT` | `8080` | Port of the health endpoint |
| `KAFKA_PRIVATE_BOOTSTRAP` | `${{RAILWAY_PRIVATE_DOMAIN}}:9092` | Bootstrap address for services in the project |
| `KAFKA_PUBLIC_BOOTSTRAP` | `${{RAILWAY_TCP_PROXY_DOMAIN}}:${{RAILWAY_TCP_PROXY_PORT}}` | Bootstrap address from outside Railway |

Optional settings (add them as variables on the service):

- `KAFKA_HEAP_OPTS` (default `-Xms256m -Xmx1g`)
- `KAFKA_NUM_PARTITIONS` (default `1`), `KAFKA_AUTO_CREATE_TOPICS` (default `true`), `KAFKA_LOG_RETENTION_HOURS` (default `168`)
- Any broker setting as `KAFKA_CFG_<NAME>`: upper case, dots become underscores. `KAFKA_CFG_LOG_RETENTION_BYTES=1073741824` sets `log.retention.bytes=1073741824`.

## Connecting

From another service in the same project, reference the variable:

```
KAFKA_BROKERS=${{Kafka.KAFKA_PRIVATE_BOOTSTRAP}}
```

No authentication is used on the private network. From outside Railway, use `KAFKA_PUBLIC_BOOTSTRAP` with these client settings:

```properties
security.protocol=SASL_PLAINTEXT
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username="kafka" password="YOUR-PASSWORD";
```

The public listener authenticates with SCRAM, so the password is never sent in clear, but the traffic itself isn't encrypted. If you only use Kafka inside Railway, delete the TCP proxy in the service's Networking settings and redeploy.

## Updates

This template builds from this repository. When the pinned Kafka version changes here, Railway shows deployers an "update available" notice and they choose when to apply it. Read `CHANGELOG.md` before applying an update. It is a single broker (replication factor 1): for production workloads that need high availability, run a multi-node cluster instead.
