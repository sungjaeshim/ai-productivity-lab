import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import vercel from '@astrojs/vercel';

export default defineConfig({
  site: 'https://blog.aisnowball.work',
  adapter: vercel(),

  image: {
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'images.unsplash.com',
      },
      {
        protocol: 'https',
        hostname: 'plus.unsplash.com',
      },
    ],
  },

  compressHTML: true,

  security: {
    csp: {
      scriptDirective: {
        resources: ["'self'"],
      },
      directives: [
        "default-src 'self'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'self'",
        "object-src 'none'",
        "img-src 'self' data: https://images.unsplash.com https://plus.unsplash.com",
        "font-src 'self' data:",
        "connect-src 'self' https:",
      ],
    },
  },

  markdown: {
    syntaxHighlight: 'prism',
  },

  sitemap: {
    site: 'https://blog.aisnowball.work',
    compress: true,
  },
  integrations: [sitemap()],
});
