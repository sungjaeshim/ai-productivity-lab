import { expect, test } from '@playwright/test';

test.describe('블로그 메인 페이지', () => {
  test('메인 페이지가 로드된다', async ({ page }) => {
    await page.goto('/');

    // 제목 확인
    await expect(page.locator('h1')).toBeVisible();

    // 내용 영역 확인
    await expect(page.locator('main')).toBeVisible();
  });

  test('네비게이션 메뉴가 있다', async ({ page }) => {
    await page.goto('/');

    // 네비게이션 확인 (헤더 내부 네비게이션)
    const header = page.locator('header').first();
    await expect(header).toBeVisible();
  });

  test('포스트 목록이 표시된다', async ({ page }) => {
    await page.goto('/');

    // 포스트 링크 확인
    const postLinks = page.locator('a[href*="/posts"], a[href*="/blog"]');
    const count = await postLinks.count();

    // 적어도 1개 이상의 포스트가 있어야 함
    expect(count).toBeGreaterThan(0);
  });

  test('모바일 반응형 레이아웃', async ({ page }) => {
    await page.goto('/');

    // 모바일 뷰포트로 변경
    await page.setViewportSize({ width: 375, height: 667 });

    // 헤더가 여전히 보이는지 확인
    const header = page.locator('header').first();
    await expect(header).toBeVisible();
  });
});
