import { github, releases } from "./links";
import { siteUrl } from "./seo";

export const apiUpdated = "2026-10-12";
export const apiDocsUrl = `${siteUrl}/api`;
export const apiMarkdownUrl = `${siteUrl}/api.md`;
export const apiCatalogUrl = `${siteUrl}/.well-known/api-catalog`;
export const openApiUrl = `${siteUrl}/openapi.json`;
export const productApiUrl = `${siteUrl}/api/product.json`;
export const healthApiUrl = `${siteUrl}/api/health.json`;

export const productFacts = {
  name: "FanBar",
  summary:
    "A free, open-source native macOS menu-bar app for monitoring temperatures and managing fan cooling.",
  homepage: siteUrl,
  repository: github,
  releases,
  license: "GPL-3.0",
  pricing: {
    amount: 0,
    currency: "USD",
    accountRequired: false,
    paidTier: false,
  },
  compatibility: {
    operatingSystem: "macOS",
    minimumVersion: "11 Big Sur",
    architectures: ["Apple Silicon", "Intel"],
    requirement: "The Mac must expose readable fan data through AppleSMC.",
    evidence: `${siteUrl}/compatibility`,
  },
  install: [
    {
      method: "DMG",
      url: releases,
      note: "Notarized builds are published on GitHub Releases.",
    },
    {
      method: "Homebrew",
      commands: [
        "brew tap helson-lin/fanbar https://github.com/helson-lin/FanBar.git",
        "brew install --cask helson-lin/fanbar/fanbar",
      ],
    },
  ],
  features: [
    "Menu-bar temperature and fan RPM monitoring",
    "Automatic cooling, fixed target RPM, and editable temperature-to-RPM curves",
    "Silent, Balanced, Performance, and Extreme presets",
    "Desktop widget on macOS 14 and later",
    "Optional high-temperature notifications",
  ],
  safety: {
    manualControlOptional: true,
    authorization:
      "Manual fan control requires explicit approval of FanBar's signed privileged helper.",
    limits: "Fan targets are clamped to the hardware-reported fan range.",
    fallback:
      "FanBar attempts to restore macOS automatic fan control when manual control ends, the app quits, the connection is lost, or the helper fails.",
  },
  languages: ["English", "Simplified Chinese", "Traditional Chinese", "Japanese"],
  updated: apiUpdated,
} as const;

export const apiHealth = {
  status: "ok",
  service: "FanBar Product Facts API",
  updated: apiUpdated,
} as const;

export const openApiDocument = {
  openapi: "3.1.0",
  info: {
    title: "FanBar Product Facts API",
    version: "1.0.0",
    description:
      "A public, read-only API exposing canonical FanBar product, compatibility, installation, and safety facts.",
    license: {
      name: "GPL-3.0",
      identifier: "GPL-3.0-only",
    },
  },
  servers: [{ url: siteUrl }],
  paths: {
    "/api/product.json": {
      get: {
        summary: "Get canonical FanBar product facts",
        operationId: "getFanBarProductFacts",
        responses: {
          "200": {
            description: "Current FanBar product facts",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/ProductFacts" },
              },
            },
          },
        },
      },
    },
    "/api/health.json": {
      get: {
        summary: "Check API publication status",
        operationId: "getFanBarApiHealth",
        responses: {
          "200": {
            description: "The static API is available",
            content: {
              "application/json": {
                schema: { $ref: "#/components/schemas/Health" },
              },
            },
          },
        },
      },
    },
  },
  components: {
    schemas: {
      ProductFacts: {
        type: "object",
        required: [
          "name",
          "summary",
          "homepage",
          "repository",
          "releases",
          "license",
          "pricing",
          "compatibility",
          "install",
          "features",
          "safety",
          "languages",
          "updated",
        ],
        properties: {
          name: { type: "string" },
          summary: { type: "string" },
          homepage: { type: "string", format: "uri" },
          repository: { type: "string", format: "uri" },
          releases: { type: "string", format: "uri" },
          license: { type: "string" },
          pricing: { type: "object", additionalProperties: true },
          compatibility: { type: "object", additionalProperties: true },
          install: {
            type: "array",
            items: { type: "object", additionalProperties: true },
          },
          features: { type: "array", items: { type: "string" } },
          safety: { type: "object", additionalProperties: true },
          languages: { type: "array", items: { type: "string" } },
          updated: { type: "string", format: "date" },
        },
      },
      Health: {
        type: "object",
        required: ["status", "service", "updated"],
        properties: {
          status: { type: "string", const: "ok" },
          service: { type: "string" },
          updated: { type: "string", format: "date" },
        },
      },
    },
  },
} as const;

export const apiCatalog = {
  linkset: [
    {
      anchor: productApiUrl,
      "service-desc": [
        {
          href: openApiUrl,
          type: "application/vnd.oai.openapi+json;version=3.1",
        },
      ],
      "service-doc": [{ href: apiDocsUrl, type: "text/html" }],
      status: [{ href: healthApiUrl, type: "application/json" }],
    },
  ],
} as const;
