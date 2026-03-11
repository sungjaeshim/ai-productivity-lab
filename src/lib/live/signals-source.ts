import fallbackSignals from '../../data/live-signals.json';

export interface LiveSignal extends Record<string, unknown> {
	id: string;
	title: string;
	summary: string;
	href: string;
	category: string;
	updatedAt: string;
	sort?: number;
}

function normalizeSignal(input: Record<string, unknown>): LiveSignal {
	return {
		id: String(input.id ?? ''),
		title: String(input.title ?? ''),
		summary: String(input.summary ?? ''),
		href: String(input.href ?? ''),
		category: String(input.category ?? 'Signal'),
		updatedAt: String(input.updatedAt ?? ''),
		sort: typeof input.sort === 'number' ? input.sort : undefined,
	};
}

function validateSignal(signal: LiveSignal): boolean {
	return Boolean(
		signal.id &&
			signal.title &&
			signal.summary &&
			signal.href &&
			signal.category &&
			signal.updatedAt,
	);
}

async function readSignalsPayload(endpoint: string, label: string): Promise<LiveSignal[]> {
	const response = await fetch(endpoint, {
		headers: {
			accept: 'application/json',
		},
	});
	if (!response.ok) {
		throw new Error(`${label} fetch failed: ${response.status}`);
	}
	const payload = await response.json();
	const items = Array.isArray(payload) ? payload : payload?.signals;
	if (!Array.isArray(items)) {
		throw new Error(`${label} did not return an array.`);
	}
	return items
		.map((item) => normalizeSignal(item as Record<string, unknown>))
		.filter(validateSignal);
}

export async function loadLiveSignalsSource(
	options: { preferFeed?: boolean } = {},
): Promise<LiveSignal[]> {
	const { preferFeed = true } = options;
	const feedEndpoint = process.env.LIVE_SIGNALS_FEED_URL?.trim();
	const sourceEndpoint =
		process.env.LIVE_SIGNALS_SOURCE_URL?.trim() || process.env.LIVE_SIGNALS_URL?.trim();

	if (preferFeed && feedEndpoint) {
		return readSignalsPayload(feedEndpoint, 'LIVE_SIGNALS_FEED_URL');
	}

	if (sourceEndpoint) {
		return readSignalsPayload(sourceEndpoint, 'LIVE_SIGNALS_SOURCE_URL');
	}

	if (!Array.isArray(fallbackSignals)) {
		throw new Error('Fallback live signals file must contain an array.');
	}

	return fallbackSignals
		.map((item) => normalizeSignal(item as Record<string, unknown>))
		.filter(validateSignal);
}
