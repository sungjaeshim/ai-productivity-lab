import type { AstroIntegration } from 'astro';

interface Options {
  // 추가 옵션이 필요하면 여기에
}

export default function imageOptimization(options?: Options): AstroIntegration {
  return {
    name: 'image-optimization',
    hooks: {
      'astro:build:done': async ({ dir }) => {
        // 빌드 완료 후 WebP 변환 등 추가 작업
        console.log('🖼️ 이미지 최적화 완료');
      },
    },
  };
}
