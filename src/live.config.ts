import { defineLiveCollection } from 'astro:content';
import { z } from 'astro/zod';

import { signalsLoader } from './lib/live/signals-loader';

const signals = defineLiveCollection({
	loader: signalsLoader(),
	schema: z.object({
		id: z.string(),
		title: z.string(),
		summary: z.string(),
		href: z.string(),
		category: z.string(),
		updatedAt: z.string(),
		sort: z.number().optional(),
	}),
});

export const collections = { signals };
