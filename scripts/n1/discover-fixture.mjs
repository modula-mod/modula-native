#!/usr/bin/env node
/**
 * Prints the public N1 Discover shape. No secrets.
 * Topics/media/featured modules are empty on N1 — Discover must render compact empty states.
 */
const url = process.env.MODULA_DISCOVER_URL ?? 'https://native-n1.modula.digital/v1/discover';
const res = await fetch(url);
if (!res.ok) {
  console.error(`GET ${url} -> ${res.status}`);
  process.exit(1);
}
const json = await res.json();
const data = json.data ?? {};
const people = data.suggestedProfiles ?? [];
const topics = data.trendingTopics ?? [];
const featured = data.featuredModules ?? [];
const media = data.media ?? [];
console.log(JSON.stringify({
  ok: json.ok === true,
  people: people.length,
  topics: topics.length,
  featuredModules: featured.length,
  media: media.length,
  handles: people.map((row) => row.handle).filter(Boolean),
}, null, 2));
