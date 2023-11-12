FROM denoland/deno:alpine
COPY ./controller/controller.ts /opt/
WORKDIR /opt/
RUN deno cache controller.ts
CMD deno run --allow-net controller.ts
