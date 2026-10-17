import type { APIRoute } from "astro";
import { siteUrl } from "@/lib/seo";

export const prerender = true;

export const GET: APIRoute = () => {
  const contentSignal = "Content-Signal: ai-train=no, search=yes, ai-input=no";
  const body = [
    "User-agent: *",
    "Allow: /",
    contentSignal,
    "",
    "User-agent: GPTBot",
    "Allow: /",
    contentSignal,
    "",
    "User-agent: ChatGPT-User",
    "Allow: /",
    contentSignal,
    "",
    "User-agent: OAI-SearchBot",
    "Allow: /",
    contentSignal,
    "",
    "User-agent: ClaudeBot",
    "Allow: /",
    contentSignal,
    "",
    "User-agent: PerplexityBot",
    "Allow: /",
    contentSignal,
    "",
    `Host: ${siteUrl}`,
    `Sitemap: ${siteUrl}/sitemap.xml`,
    "",
  ].join("\n");

  return new Response(body, {
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
};
