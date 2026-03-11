import type { LiveLoader } from 'astro/loaders';

import { loadLiveSignalsSource, type LiveSignal } from './signals-source';

interface EntryFilter {
	id?: string;
}

interface CollectionFilter {
	category?: string;
	limit?: number;
}

export function signalsLoader(): LiveLoader<LiveSignal, EntryFilter, CollectionFilter> {
	return {
		name: 'ai-snowball-signals',
		loadCollection: async ({ filter }) => {
			try {
				let entries = await loadLiveSignalsSource();
				if (filter?.category) {
					entries = entries.filter((entry) => entry.category === filter.category);
				}
				if (typeof filter?.limit === 'number') {
					entries = entries.slice(0, filter.limit);
				}
				return {
					entries: entries.map((entry) => ({
						id: entry.id,
						data: entry,
					})),
				};
			} catch (error) {
				return {
					error: new Error('Failed to load live signals.', { cause: error }),
				};
			}
		},
		loadEntry: async ({ filter }) => {
			try {
				const entries = await loadLiveSignalsSource();
				const id = filter.id;
				if (!id) {
					return {
						error: new Error('Signal id is required.'),
					};
				}
				const entry = entries.find((item) => item.id === id);
				if (!entry) {
					return {
						error: new Error('Signal not found.'),
					};
				}
				return {
					id: entry.id,
					data: entry,
				};
			} catch (error) {
				return {
					error: new Error('Failed to load live signal entry.', { cause: error }),
				};
			}
		},
	};
}
