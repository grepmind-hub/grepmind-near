/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  assetPrefix: '/merchant',
  async rewrites() {
    return [{
      source: '/api/v1/:path*',
      destination: `${process.env.API_PROXY_TARGET || 'http://api:8080/api/v1'}/:path*`,
    }];
  },
  images: {
    remotePatterns: [
      {
        protocol: 'http',
        hostname: '**',
      },
      {
        protocol: 'https',
        hostname: '**',
      },
    ],
  },
};

module.exports = nextConfig;
