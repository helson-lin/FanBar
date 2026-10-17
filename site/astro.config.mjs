import { defineConfig } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  site: "https://fanbar.jarin.me",
  output: "static",
  trailingSlash: "never",
  vite: {
    plugins: [tailwindcss()],
  },
});
