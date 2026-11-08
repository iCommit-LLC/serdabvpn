import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Standalone output so the Docker image runs `node server.js` without the
  // full node_modules tree (same pattern as icommit-dashboard).
  output: "standalone",
  poweredByHeader: false,
};

export default nextConfig;
