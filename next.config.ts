import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  allowedDevOrigins: ["*.replit.dev", "*.repl.co", "*.replit.app"],
  serverExternalPackages: ["pdfkit"],
};

export default nextConfig;
