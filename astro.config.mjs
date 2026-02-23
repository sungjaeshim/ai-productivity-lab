import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://aisnowball.work',
  sitemap: {
    site: 'https://aisnowball.work',
    compress: true,
  },
  integrations: [sitemap()],
});
