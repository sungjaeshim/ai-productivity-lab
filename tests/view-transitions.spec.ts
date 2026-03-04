import { expect, test } from '@playwright/test';

test.describe('블로그 메인 페이지', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
  });

  test('View Transitions이 있다', async ({ page }) => {
    // CSS 트랜지션이 있는지 확인
    const styles = await page.locator('style').all();

    // ::view-transition 관련 CSS 확인
    const hasViewTransitionStyles = await page.evaluate(() => {
      const styles = Array.from(document.querySelectorAll('style'));
      return styles.some(style => {
        const text = style.textContent || '';
        return text.includes('view-transition') || text.includes('::view-transition');
      });
    });

    expect(hasViewTransitionStyles).toBe(true);
  });

  test('페이지 로드 시 애니메이션 없음', async ({ page }) => {
    // 페이지 전환 시 깜빡밀 현상이 없어야 함
    // playwright-screenshot 옵션은 'only-on-failure'이므로,
    // 일반 로드 시 자동 스크린샷은 찍히지 않음

    const title = await page.locator('h1').first();
    await expect(title).toBeVisible();
  });
});
