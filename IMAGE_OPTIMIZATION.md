---
---

# Image Optimization Demo

Astro v5 내장 이미지 최적화 사용법:

## 1. OptimizedImage 컴포넌트 사용

```astro
---
import OptimizedImage from '../components/OptimizedImage.astro';
---

<OptimizedImage
  src="/images/hero.jpg"
  alt="블로그 헤더 이미지"
  width={1200}
  height={630}
/>
```

## 2. 일반 Astro <Image> 사용 (추천)

```astro
---
import { Image } from 'astro:assets';
---

<Image
  src="/images/hero.jpg"
  alt="블로그 헤더 이미지"
  width={1200}
  height={630}
  format="webp"  // 자동 WebP 변환
  loading="lazy"   // lazy loading
  quality={80}     // 품질 설정
/>
```

## 3. 반응형 이미지

```astro
<Image
  src="/images/hero.jpg"
  alt="반응형 이미지"
  widths={[400, 800, 1200]}  // 여러 크기 자동 생성
  sizes="(max-width: 400px) 400px, 800px, 1200px"
  loading="lazy"
/>
```

## 4. astro.config.mjs 설정

```javascript
image: {
  // 원격 이미지 허용 도메인
  remotePatterns: [],

  // 이미지 서비스 설정
  service: {
    entrypoint: 'astro/assets/services/sharp',
    config: {
      oneOffConcurrency: 1,
      limitConcurrentOperations: 50,
    },
  },
}
```

## 주요 이점

| 기능 | Astro v5 내장 |
|------|--------------|
| WebP 변환 | ✅ 자동 |
| 반응형 이미지 | ✅ srcset |
| lazy loading | ✅ loading="lazy" |
| 블러 플레이스홀더 | ✅ 자동 |
| 최적화된 CDN | ✅ 선택 가능 |

참고: [Astro Image Docs](https://docs.astro.build/en/guides/images/)
