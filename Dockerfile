# Apache Kafka for Railway: single-node KRaft broker (no ZooKeeper).
# Pinned by version and digest. To update: bump both, add a CHANGELOG entry, test on a branch.
FROM apache/kafka:4.4.0@sha256:833b867a9585a141da455dc2b57431c65cbccb27f11c91f694444cca9f777e0f

# Railway volumes are mounted as root, so the broker runs as root inside the container.
USER root

COPY --chmod=755 start.sh /usr/local/bin/railway-kafka-start
COPY --chmod=755 health.sh /usr/local/bin/railway-kafka-health

# 9092: private network (plaintext), 9094: public TCP proxy (SASL/SCRAM), 8080: health check
EXPOSE 9092 9094 8080

ENTRYPOINT ["/usr/local/bin/railway-kafka-start"]
