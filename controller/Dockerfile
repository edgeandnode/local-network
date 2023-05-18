FROM denoland/deno:alpine
COPY ./controller/controller.ts /opt/
WORKDIR /opt/
CMD deno run --allow-net controller.ts
