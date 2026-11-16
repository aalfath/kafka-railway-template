# Changelog

## 4.4.0-1 (2026-11-16)

- README: Deploy on Railway button for the published template `apache-kafka-1`. No change to the broker.


## 4.4.0 (2026-11-16)

- First release: Apache Kafka 4.4.0 (`apache/kafka:4.4.0@sha256:833b867a9585a141da455dc2b57431c65cbccb27f11c91f694444cca9f777e0f`), single-node KRaft.
- Private plaintext listener on port 9092, public SASL/SCRAM listener through a Railway TCP proxy (port 9094), health endpoint on `PORT`.
- Data and cluster id on the volume at `/var/lib/kafka`.
