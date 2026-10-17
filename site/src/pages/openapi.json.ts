import type { APIRoute } from "astro";
import { openApiDocument } from "@/lib/api";

export const prerender = true;

export const GET: APIRoute = () =>
  new Response(`${JSON.stringify(openApiDocument, null, 2)}\n`, {
    headers: {
      "Content-Type": "application/vnd.oai.openapi+json;version=3.1; charset=utf-8",
    },
  });
