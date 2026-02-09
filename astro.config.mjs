import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://ai-productivity-tips.vercel.app',
  integrations: [sitemap()],
});
