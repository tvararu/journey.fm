import node from "@astrojs/node";
import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "astro/config";

export default defineConfig({
  adapter: node({ mode: "standalone" }),
  compressHTML: true,
  output: "server",
  server: { host: "127.0.0.1", port: Number(process.env.PORT) || 8786 },
  vite: {
    plugins: [tailwindcss()],
    resolve: { alias: { "@": `${import.meta.dirname}/src` } },
    ssr: { external: ["bun", "bun:sqlite"] },
    build: { rolldownOptions: { external: ["bun", "bun:sqlite"] } },
  },
});
