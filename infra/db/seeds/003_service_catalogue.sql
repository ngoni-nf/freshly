-- ============================================================================
-- The service catalogue, from the provider taxonomy and skills matrix.
--
-- Reference data, not demo data: this ships to production. Durations are the
-- realistic middle of each service, because they seed a provider's diary — a
-- knotless braid set booked at 45 minutes would wreck their day.
--
-- requires_power marks anything needing mains: clippers, lasers, LED, steam,
-- an autoclave. It feeds the load-shedding filter, which is why a braider is
-- bookable at stage 6 and a colourist is not.
--
-- is_invasive marks what breaks skin or fires a regulated device. The
-- credential trigger reads it directly, so listing one of these without a
-- verified licence is refused by the database.
-- ============================================================================

INSERT INTO service_templates
  (category, slug, name, description, typical_duration_minutes, requires_power, is_invasive, sort_order)
VALUES
-- 1A. Master barber
('barber','skin-fade','Skin fade','Taper, drop, burst or temp fade, shaped up.',45,true,false,1),
('barber','scissor-cut','Scissor cut','Scissor work throughout, no clippers.',45,false,false,2),
('barber','textured-top','Texturized top','Texture and movement through the top.',40,true,false,3),
('barber','line-up','Line-up / shape-up','Edges and hairline only.',20,true,false,4),
('barber','buzz-cut','Buzz cut','One length all over.',20,true,false,5),
('barber','hair-tattoo','Freestyle hair tattoo','Clipper design work, freehand.',60,true,false,6),
('barber','kids-cut','Kids cut','Under 12s.',30,true,false,7),

-- 1B. Beard and facial hair
('beard','beard-trim','Beard trim and sculpt','Shaped, trimmed and balanced.',30,true,false,1),
('beard','hot-towel-shave','Hot towel straight-razor shave','Full shave, hot towel, finishing balm.',45,false,false,2),
('beard','beard-line-edge','Beard line edging','Cheek and neck lines only.',20,true,false,3),
('beard','beard-colour','Beard colour blending','Grey blending or full colour.',45,false,false,4),
('beard','beard-conditioning','Beard steam and deep conditioning','Steam, mask and oil.',30,true,false,5),

-- 1C. Scalp and restoration
('scalp','scalp-detox','Scalp detox and exfoliation','Clarifying treatment and massage.',45,true,false,1),
('scalp','thinning-treatment','Hair thinning treatment','Density products and scalp stimulation.',45,true,false,2),
('scalp','dandruff-massage','Anti-dandruff scalp massage','Medicated treatment and massage.',40,false,false,3),
('scalp','smp','Scalp micropigmentation','Pigment implanted into the scalp. Licensed practitioners only.',180,true,true,4),

-- 2A. Braiding and locs
('braiding','knotless-braids','Knotless braids','Hair not included unless agreed.',240,false,false,1),
('braiding','box-braids','Box braids','Hair not included unless agreed.',240,false,false,2),
('braiding','cornrows','Cornrows / feed-in braids','Straight back or patterned.',90,false,false,3),
('braiding','passion-twists','Passion twists','Hair not included unless agreed.',210,false,false,4),
('braiding','faux-locs','Faux locs','Hair not included unless agreed.',300,false,false,5),
('locs','loc-install','Dreadlock installation','Starter locs, sectioned and set.',240,false,false,1),
('locs','loc-retwist','Loc retwist','Roots retwisted and styled.',120,false,false,2),
('locs','sisterlocks','Sisterlocks','Micro-sized locs, installation or retightening.',300,false,false,3),
('locs','loc-detox','Loc detox','Deep clean and residue removal.',90,true,false,4),

-- 2B. Weaves, wigs and extensions
('extensions','wig-install-glueless','Glueless wig installation','Fitted and styled, no adhesive.',90,true,false,1),
('extensions','wig-install-lace','Lace front wig installation','Laid, tinted and styled.',120,true,false,2),
('extensions','wig-customisation','Wig customisation','Plucking, knot bleaching and shaping.',120,false,false,3),
('extensions','sew-in','Sew-in weave','Braided base and sewn wefts.',180,false,false,4),
('extensions','tape-ins','Tape-in extensions','Applied and blended.',120,true,false,5),
('extensions','microlinks','Microlinks / I-tips','Bead and thread application.',180,false,false,6),

-- 2C. Colour and chemical
('color','balayage','Balayage','Hand-painted, toned and finished.',180,true,false,1),
('color','foil-highlights','Foil highlights','Foiled, toned and finished.',150,true,false,2),
('color','bleach-tone','Full bleach and tone','Lift and tone. Consultation required.',210,true,false,3),
('color','colour-correction','Colour correction','Consultation required before booking.',300,true,false,4),
('color','relaxer','Relaxer / texturizer','Chemical straightening.',120,false,false,5),
('color','keratin','Keratin treatment','Smoothing treatment, heat sealed.',180,true,false,6),
('color','brazilian-blowout','Brazilian blowout','Smoothing and finish.',180,true,false,7),

-- 2D. Precision cut and heat
('hair','precision-cut','Precision cut','Bob, pixie or layered cut.',60,true,false,1),
('hair','silk-press','Silk press','Wash, blow-dry and flat iron.',120,true,false,2),
('hair','blowout','Blowout','Wash and round-brush finish.',60,true,false,3),
('hair','updo','Updo / event styling','Occasion styling.',90,true,false,4),
('hair','thermal-styling','Thermal styling','Flat iron or wand curls.',60,true,false,5),

-- 3A. Acrylic and gel extensions
('nails','acrylic-full-set','Acrylic full set','Sculpted or tipped, shaped and finished.',120,true,false,1),
('nails','acrylic-infill','Acrylic infill','Regrowth filled and rebalanced.',90,true,false,2),
('nails','hard-gel','Hard gel extensions','Sculpted hard gel.',120,true,false,3),
('nails','biab','Builder gel (BIAB)','Overlay on the natural nail.',90,true,false,4),
('nails','polygel','Polygel','Sculpted polygel extensions.',120,true,false,5),
('nails','nail-art-3d','3D nail art','Freehand and sculpted detail.',60,true,false,6),
('nails','chrome-encapsulated','Chrome / encapsulated design','Chrome, foil or encapsulated finish.',45,true,false,7),

-- 3B. Natural nails and pedicure
('nails','classic-manicure','Classic manicure','Shape, cuticle work and polish.',45,false,false,8),
('nails','classic-pedicure','Classic pedicure','Soak, shape, cuticle work and polish.',60,true,false,9),
('nails','gel-polish','Gel polish','Shellac on the natural nail.',60,true,false,10),
('nails','russian-manicure','Russian dry manicure','E-file cuticle preparation.',75,true,false,11),
('nails','callus-peel','Callus peel treatment','Chemical peel and blade work.',45,false,false,12),
('nails','paraffin-wax','Paraffin wax hydration','Warm wax treatment for hands or feet.',30,true,false,13),

-- 4A. Makeup
('makeup','soft-glam','Soft glam','Natural finish with definition.',60,false,false,1),
('makeup','full-glam','Full glam','Full coverage, lashes included.',90,false,false,2),
('makeup','bridal-makeup','Bridal makeup','Trial recommended before the day.',120,false,false,3),
('makeup','airbrush','Airbrush makeup','Airbrush foundation and finish.',90,true,false,4),
('makeup','editorial','Editorial / photoshoot makeup','Camera-ready.',90,false,false,5),
('makeup','sfx-accents','Special effects accents','SFX detail work.',90,false,false,6),

-- 4B. Lashes
('lashes','classic-lashes','Classic lash extensions','One extension per natural lash.',120,false,false,1),
('lashes','hybrid-lashes','Hybrid lashes','Classic and volume mixed.',135,false,false,2),
('lashes','volume-lashes','Volume lashes','Handmade fans.',150,false,false,3),
('lashes','mega-volume','Mega volume lashes','Dense handmade fans.',180,false,false,4),
('lashes','lash-lift','Lash lift and tint','Lifted and tinted natural lashes.',60,false,false,5),

-- 4C. Brows and PMU
('brows','brow-lamination','Brow lamination','Set and shaped, tint optional.',60,false,false,1),
('brows','brow-shaping','Brow mapping, threading or wax','Mapped and shaped.',30,false,false,2),
('brows','henna-brows','Henna brows','Stained and shaped.',45,false,false,3),
('brows','microblading','Microblading','Blade-implanted pigment. Licensed practitioners only.',150,false,true,4),
('brows','ombre-powder-brows','Ombre powder brows','Machine-implanted pigment. Licensed practitioners only.',180,true,true,5),
('brows','lip-blush','Lip blush','Machine-implanted lip pigment. Licensed practitioners only.',180,true,true,6),

-- 5A. Skincare
('aesthetics','deep-cleansing-facial','Deep cleansing facial','Cleanse, extract and mask.',60,true,false,1),
('aesthetics','chemical-peel','Chemical peel','Controlled peel. Licensed practitioners only.',60,false,true,2),
('aesthetics','dermaplaning','Dermaplaning','Scalpel exfoliation. Licensed practitioners only.',45,false,true,3),
('aesthetics','microneedling','Microneedling','Collagen induction. Licensed practitioners only.',75,true,true,4),
('aesthetics','led-therapy','LED light therapy','Light therapy session.',30,true,false,5),
('aesthetics','hydrafacial','Hydrafacial','Cleanse, extract and hydrate.',60,true,false,6),
('aesthetics','high-frequency','High-frequency acne treatment','High-frequency and extraction.',45,true,false,7),

-- 5B. Body grooming and hair removal
('body_grooming','brazilian-wax','Brazilian wax','Hard wax.',45,true,false,1),
('body_grooming','hollywood-wax','Hollywood wax','Hard wax, everything removed.',50,true,false,2),
('body_grooming','full-body-wax','Full body waxing','Legs, arms and body.',120,true,false,3),
('body_grooming','body-threading','Body threading','Threading for face or body.',30,false,false,4),
('body_grooming','sugaring','Sugaring','Sugar paste hair removal.',60,true,false,5),
('body_grooming','laser-hair-removal','Laser hair removal','Regulated device. Licensed operators only.',45,true,true,6),
('body_grooming','manscaping','Male body grooming','Trim and tidy, back and body.',60,true,false,7),

-- 5C. Massage
('massage','swedish-massage','Swedish massage','Full body, relaxing pressure.',60,false,false,1),
('massage','deep-tissue','Deep tissue massage','Firm pressure, focused work.',60,false,false,2),
('massage','hot-stone','Hot stone therapy','Heated stones and massage.',90,true,false,3),
('massage','sports-recovery','Sports recovery massage','Recovery-focused.',60,false,false,4),
('massage','lymphatic-drainage','Lymphatic drainage massage','Light, directional technique.',75,false,false,5)

ON CONFLICT (slug) DO UPDATE
  SET name = EXCLUDED.name,
      description = EXCLUDED.description,
      typical_duration_minutes = EXCLUDED.typical_duration_minutes,
      requires_power = EXCLUDED.requires_power,
      is_invasive = EXCLUDED.is_invasive,
      sort_order = EXCLUDED.sort_order;
