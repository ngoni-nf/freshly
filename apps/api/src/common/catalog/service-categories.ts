/**
 * The service taxonomy, in one place.
 *
 * It was previously written out by hand in the discovery DTO, the AI intent
 * parser and the Dart client, which is how 'brows_lashes' ended up meaning two
 * different specializations. Adding a category is now one edit here plus the
 * enum migration.
 *
 * Must stay in step with service_category_enum. The database is authoritative;
 * this list exists so a bad value is rejected at the edge with a useful
 * message instead of as a Postgres cast error.
 */
export const SERVICE_CATEGORIES = [
  // 1. Barbering and men's grooming
  'barber',
  'beard',
  'scalp',
  // 2. Hair styling and hair care
  'hair',
  'braiding',
  'locs',
  'extensions',
  'color',
  // 3. Nail technology
  'nails',
  // 4. Makeup, lash and brow artistry
  'makeup',
  'lashes',
  'brows',
  // 5. Aesthetics, skincare and body grooming
  'aesthetics',
  'body_grooming',
  'massage',
] as const;

export type ServiceCategory = (typeof SERVICE_CATEGORIES)[number];
