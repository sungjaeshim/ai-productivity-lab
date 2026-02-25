import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://blog.aisnowball.work',

  // 이미지 최적화 설정
  image: {
    // 원격 이미지 허용 도메인
    remotePatterns: [],
  },

  // 빌드 결과 최적화
  compressHTML: true,
  compressCSS: true,

  sitemap: {
    site: 'https://blog.aisnowball.work',
    compress: true,
  },
  integrations: [sitemap()],
});
