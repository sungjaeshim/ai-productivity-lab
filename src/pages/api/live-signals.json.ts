export const prerender = false;

import { loadLiveSignalsSource } from '../../lib/live/signals-source';

export async function GET() {
	const signals = await loadLiveSignalsSource({ preferFeed: false });
	return Response.json(
		{
			signals,
			meta: {
				source:
					process.env.LIVE_SIGNALS_SOURCE_URL?.trim() ||
					process.env.LIVE_SIGNALS_URL?.trim() ||
					'local-fallback',
				count: signals.length,
			},
		},
		{
			headers: {
				'cache-control': 's-maxage=300, stale-while-revalidate=3600',
			},
		},
	);
}
