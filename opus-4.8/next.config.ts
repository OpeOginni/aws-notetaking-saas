import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Produce a standalone build for a small production Docker image.
  output: "standalone",
  // Allow images served from the app's S3-backed proxy route.
  images: {
    remotePatterns: [
      { protocol: "https", hostname: "**" },
    ],
  },
  eslint: {
    ignoreDuringBuilds: true,
  },
  typescript: {
    ignoreBuildErrors: false,
  },
};

export default nextConfig;
