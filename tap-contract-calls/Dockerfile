FROM python:3.9-slim-buster
RUN apt-get update && \
    apt-get install -y ca-certificates curl git jq  && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /opt/

COPY ./tap-contract-calls/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt


COPY ./tap-contract-calls /opt
COPY ./.env /opt

RUN chmod +x run.sh

CMD sh ./run.sh
