import type { APIRoute } from "astro";
import { apiCatalog, apiCatalogUrl } from "@/lib/api";

export const prerender = true;

const headers = {
  "Content-Type":
    'application/linkset+json; profile="https://www.rfc-editor.org/info/rfc9727"',
  Link: `<${apiCatalogUrl}>; rel="api-catalog"`,
};

export const GET: APIRoute = () =>
  new Response(`${JSON.stringify(apiCatalog, null, 2)}\n`, { headers });

export const HEAD: APIRoute = () => new Response(null, { headers });
