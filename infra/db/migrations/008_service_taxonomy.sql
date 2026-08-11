-- ---------------------------------------------------------------------------
-- Service taxonomy: one enum value per provider specialization.
--
-- The original nine values were inconsistent about granularity. They split
-- braiding from locs, which are one specialization (a loctician braids), while
-- merging brows with lashes, which are two — different training, different
-- kit, different insurance. Four specializations had no home at all and were
-- being filed under 'hair' or nothing: weaves and extensions, colour and
-- chemical work, beard specialists, and body grooming.
--
-- ALTER TYPE ... ADD VALUE is transaction-safe on PostgreSQL 12 and later, but
-- the new labels cannot be *used* until the transaction commits. That is why
-- everything which reads or writes them lives in 009 rather than here.
--
-- Enum order is not semantic anywhere in this codebase; nothing sorts by
-- category, so the new labels are simply appended.
-- ---------------------------------------------------------------------------

-- 4B and 4C are separate specializations. A lash tech isolating individual
-- lashes and a PMU artist implanting pigment into the dermis have almost
-- nothing in common, and after 009 only one of them needs a licence.
ALTER TYPE service_category_enum RENAME VALUE 'brows_lashes' TO 'brows';
ALTER TYPE service_category_enum ADD VALUE IF NOT EXISTS 'lashes';

-- 1B: beard and facial hair specialists.
ALTER TYPE service_category_enum ADD VALUE IF NOT EXISTS 'beard';

-- 1C: scalp care and hair restoration, including SMP.
ALTER TYPE service_category_enum ADD VALUE IF NOT EXISTS 'scalp';

-- 2B: weaves, wigs and extensions.
ALTER TYPE service_category_enum ADD VALUE IF NOT EXISTS 'extensions';

-- 2C: colour and chemical work — bleach, relaxers, keratin.
ALTER TYPE service_category_enum ADD VALUE IF NOT EXISTS 'color';

-- 5B: waxing, sugaring, threading, laser.
ALTER TYPE service_category_enum ADD VALUE IF NOT EXISTS 'body_grooming';
