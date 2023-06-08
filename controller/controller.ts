import { serve } from "https://deno.land/std@0.188.0/http/server.ts";
import { sleep } from "https://deno.land/x/sleep@v1.2.1/sleep.ts";

const state = new Map<string, string>();

async function handleRequest(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const key = url.pathname.split("/")[1];
  const body = await request.text();
  console.log({ method: request.method, key, body });
  switch (request.method) {
    case "GET": {
      if (key == "") {
        return new Response(
          JSON.stringify(Object.fromEntries(state.entries())),
          { status: 200 },
        );
      }
      while (!state.has(key)) {
        await sleep(1);
      }
      return new Response(state.get(key)!, { status: 200 });
    }
    case "POST": {
      if (state.has(key) && state.get(key) != body) {
        console.log("  WARN", { previousValue: state.get(key) });
      }
      state.set(key, body);
      return new Response(body, { status: 200 });
    }
    default:
      return new Response("Method not allowed", { status: 404 });
  }
}

await serve(handleRequest, { hostname: "0.0.0.0", port: 6001 });
