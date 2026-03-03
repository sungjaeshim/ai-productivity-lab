import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const blog = defineCollection({
	loader: glob({ base: './src/content/blog', pattern: '**/*.{md,mdx}' }),
	schema: z
		.object({
			title: z.string(),
			description: z.string(),
			pubDate: z.coerce.date().optional(),
			date: z.coerce.date().optional(), // backward-compat alias
			updatedDate: z.coerce.date().optional(),
			heroImage: z.string().optional(),
			heroImageAlt: z.string().optional(),
			heroImageCredit: z.string().optional(),
			tags: z.array(z.string()).default([]),
		})
		.refine((data) => Boolean(data.pubDate || data.date), {
			message: 'Either pubDate or date is required',
			path: ['pubDate'],
		})
		.transform((data) => ({
			...data,
			pubDate: data.pubDate ?? data.date!,
		})),
});

export const collections = { blog };
