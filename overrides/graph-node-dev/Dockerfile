FROM rust:latest
RUN apt-get update && apt-get install -y curl protobuf-compiler
COPY ./run-override.sh /opt/run-override.sh
ENTRYPOINT bash -cl /opt/run-override.sh
