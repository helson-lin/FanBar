import type { APIRoute } from "astro";
import { productFacts } from "@/lib/api";

export const prerender = true;

export const GET: APIRoute = () =>
  new Response(`${JSON.stringify(productFacts, null, 2)}\n`, {
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
