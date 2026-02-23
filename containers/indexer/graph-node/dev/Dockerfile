FROM rust:latest
RUN apt-get update && apt-get install -y curl protobuf-compiler gdb gdbserver
COPY ./run-override.sh /opt/run-override.sh
ENTRYPOINT ["bash", "/opt/run-override.sh"]
