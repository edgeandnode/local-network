#!/bin/bash


docker compose down indexer-agent
docker compose build indexer-agent
docker compose create indexer-agent
docker compose start indexer-agent

