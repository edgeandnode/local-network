"""
IISA scoring service for local network.

Long-running service that ensures indexer scores are available for the
IISA HTTP service. On startup writes seed scores so IISA can start
immediately, then periodically checks Redpanda for real query data
and refreshes scores when available.

Modelled after the eligibility-oracle-node polling pattern.
"""

import json
import logging
import os
import shutil
import signal
import sys
import time
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("iisa-scoring")

SCORES_FILE_PATH = os.environ.get("SCORES_FILE_PATH", "/app/scores/indexer_scores.json")
SEED_SCORES_PATH = "/app/seed_scores.json"
REDPANDA_BOOTSTRAP_SERVERS = os.environ.get("REDPANDA_BOOTSTRAP_SERVERS", "")
REDPANDA_TOPIC = os.environ.get("REDPANDA_TOPIC", "gateway_queries")
REFRESH_INTERVAL = int(os.environ.get("IISA_SCORING_INTERVAL", "600"))  # 10 minutes

# Graceful shutdown
shutdown_requested = False


def handle_signal(signum, frame):
    global shutdown_requested
    logger.info(f"Received signal {signum}, shutting down")
    shutdown_requested = True


signal.signal(signal.SIGTERM, handle_signal)
signal.signal(signal.SIGINT, handle_signal)


def count_redpanda_messages() -> int:
    """Count messages in the Redpanda gateway_queries topic. Returns 0 on error."""
    if not REDPANDA_BOOTSTRAP_SERVERS:
        return 0

    try:
        from confluent_kafka import Consumer, TopicPartition

        consumer = Consumer({
            "bootstrap.servers": REDPANDA_BOOTSTRAP_SERVERS,
            "group.id": "iisa-scoring-check",
            "auto.offset.reset": "earliest",
            "enable.auto.commit": False,
        })

        metadata = consumer.list_topics(topic=REDPANDA_TOPIC, timeout=10)
        topic_metadata = metadata.topics.get(REDPANDA_TOPIC)

        if topic_metadata is None or topic_metadata.error is not None:
            consumer.close()
            return 0

        partitions = topic_metadata.partitions
        if not partitions:
            consumer.close()
            return 0

        total = 0
        for partition_id in partitions:
            tp = TopicPartition(REDPANDA_TOPIC, partition_id)
            low, high = consumer.get_watermark_offsets(tp, timeout=10)
            total += high - low

        consumer.close()
        return total

    except Exception as e:
        logger.warning(f"Failed to check Redpanda: {e}")
        return 0


def write_seed_scores() -> bool:
    """Copy seed scores file to the scores output path. Returns True on success."""
    scores_path = Path(SCORES_FILE_PATH)
    scores_path.parent.mkdir(parents=True, exist_ok=True)

    if not Path(SEED_SCORES_PATH).exists():
        logger.error(f"Seed scores file not found: {SEED_SCORES_PATH}")
        return False

    shutil.copy2(SEED_SCORES_PATH, SCORES_FILE_PATH)

    with open(SCORES_FILE_PATH) as f:
        data = json.load(f)

    logger.info(f"Wrote seed scores ({len(data)} indexers) to {SCORES_FILE_PATH}")
    return True


def ensure_scores_exist() -> bool:
    """Ensure a scores file exists. Returns True if scores are available."""
    if Path(SCORES_FILE_PATH).exists():
        try:
            with open(SCORES_FILE_PATH) as f:
                data = json.load(f)
            if data:
                logger.info(f"Scores file exists with {len(data)} indexers")
                return True
        except (json.JSONDecodeError, OSError):
            logger.warning("Existing scores file is invalid, will overwrite")

    return write_seed_scores()


def try_compute_scores() -> bool:
    """
    Attempt to compute real scores from Redpanda data.

    TODO: Integrate the actual CronJob score computation pipeline here.
    For now, logs the message count and returns False (uses seed scores).
    """
    msg_count = count_redpanda_messages()

    if msg_count == 0:
        logger.info("No messages in Redpanda yet, keeping current scores")
        return False

    # TODO: Run actual score computation from Redpanda data when the
    # CronJob pipeline is integrated into this container. The pipeline
    # needs: protobuf decoding, linear regression, GeoIP resolution.
    logger.info(
        f"Redpanda has ~{msg_count} messages. "
        "CronJob integration pending, keeping current scores."
    )
    return False


def main() -> int:
    logger.info("IISA scoring service starting")
    logger.info(f"Refresh interval: {REFRESH_INTERVAL}s")
    logger.info(f"Scores file: {SCORES_FILE_PATH}")
    logger.info(f"Redpanda: {REDPANDA_BOOTSTRAP_SERVERS or '(not configured)'}")

    # Phase 1: Ensure scores exist so IISA can start
    if not ensure_scores_exist():
        logger.error("Failed to initialize scores, exiting")
        return 1

    logger.info("Initial scores ready, entering refresh loop")

    # Phase 2: Periodic refresh loop
    while not shutdown_requested:
        for _ in range(REFRESH_INTERVAL):
            if shutdown_requested:
                break
            time.sleep(1)

        if shutdown_requested:
            break

        logger.info("Running periodic score refresh")
        try_compute_scores()

    logger.info("IISA scoring service stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
