FROM denoland/deno:alpine-1.40.4
COPY ./controller/controller.ts /opt/
WORKDIR /opt/
RUN deno cache controller.ts
CMD deno run --allow-net --allow-read --allow-write controller.ts
