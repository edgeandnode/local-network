FROM denoland/deno:alpine
RUN apk update && apk add --no-cache curl
COPY ./controller/controller.ts /opt/
WORKDIR /opt/
RUN deno cache controller.ts
CMD deno run --allow-net controller.ts
