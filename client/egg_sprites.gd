extends RefCounted
class_name EggSprites

## Which egg SPRITE stands for each cosmetic variant.
##
## Owner 2026-09-08: *"It would be cool if we could somehow have like a dictionary where you could
## tell what type of variant you are going to get by the artwork of the egg."* This is that
## dictionary. An egg's art now tells you what you are going to hatch before you hatch it.
##
## GENERATED, not hand-written. Every egg in `pet-egg-pack` was opened and its dominant body
## colour measured from the actual pixels, then each entry in `DropTables.EGG_VARIANTS` was
## matched to the nearest egg by RGB distance. Filenames were deliberately NOT trusted: they
## carry colour WORDS ("red-blue"), and a red-blue egg turns out to be a blended purple, so the
## name describes the inputs rather than what the player sees.
##
## Two measurement notes worth keeping, both mistakes caught before they shipped:
##   * Near-black pixels are only discarded as OUTLINE when they are a minority. Discarding them
##     unconditionally meant a black egg could never match a black variant, and sent Obsidian,
##     Eclipse, Void, Barcode and Jailbird to pale eggs.
##   * A "spread the picks out" penalty was tuned by measurement rather than taste: at 0 it gave
##     39 distinct eggs, at 9000 it forced 14 bad colour matches. At 2000 it gives 95 distinct
##     eggs with 3 poor matches - Harlequin, Neon Bars and Bifrost, which are multi-colour
##     novelty variants no single-hue egg can represent. Those are the recolour candidates.
##
## Owner accepted the PATTERN loss (striped / split_v / checker cannot survive a sprite) and
## accepted collisions: 24 variants share an egg with a near-identical-coloured one.
##
## To regenerate after adding variants or eggs, re-run the generator described above rather than
## editing entries by hand - a hand-edited row is a second source of truth.

const SPRITE_BY_VARIANT := {
	"Crimson": "res://client/sprites/pet-egg-pack/eggs/named/0615-ruby.png",
	"Azure": "res://client/sprites/pet-egg-pack/eggs/named/0510-photon-frost.png",
	"Verdant": "res://client/sprites/pet-egg-pack/eggs/named/0527-toxic-confetti.png",
	"Silver": "res://client/sprites/pet-egg-pack/eggs/colorways/0229-white-cream.png",
	"Amber": "res://client/sprites/pet-egg-pack/eggs/named/0618-solar-slush.png",
	"Obsidian": "res://client/sprites/pet-egg-pack/eggs/named/0487-comet-tail.png",
	"Scarlet": "res://client/sprites/pet-egg-pack/eggs/colorways/0189-red-orange.png",
	"Cobalt": "res://client/sprites/pet-egg-pack/eggs/named/0514-quasar-ice.png",
	"Golden": "res://client/sprites/pet-egg-pack/eggs/colorways/0396-yellow-gold.png",
	"Shadow": "res://client/sprites/pet-egg-pack/eggs/colorways/0012-black.png",
	"Violet": "res://client/sprites/pet-egg-pack/eggs/named/0470-amethyst-veil.png",
	"Coral": "res://client/sprites/pet-egg-pack/eggs/colorways/0208-orange-tan-variant-3.png",
	"Teal": "res://client/sprites/pet-egg-pack/eggs/named/0580-void-laser.png",
	"Rose": "res://client/sprites/pet-egg-pack/eggs/named/0530-acid-cabaret.png",
	"Lime": "res://client/sprites/pet-egg-pack/eggs/named/0565-plasma-lime.png",
	"Copper": "res://client/sprites/pet-egg-pack/eggs/colorways/0010-orange.png",
	"Frost": "res://client/sprites/pet-egg-pack/eggs/named/0494-greece.png",
	"Infernal": "res://client/sprites/pet-egg-pack/eggs/named/0604-koi-arcade.png",
	"Toxic": "res://client/sprites/pet-egg-pack/eggs/named/0512-plasma-meadow.png",
	"Amethyst": "res://client/sprites/pet-egg-pack/eggs/colorways/0198-purple-white.png",
	"Midnight": "res://client/sprites/pet-egg-pack/eggs/named/0550-greece.png",
	"Ivory": "res://client/sprites/pet-egg-pack/eggs/named/0624-egg-base.png",
	"Rust": "res://client/sprites/pet-egg-pack/eggs/named/0502-martian-dust.png",
	"Mint": "res://client/sprites/pet-egg-pack/eggs/colorways/0365-cyan-cream.png",
	"Sunset": "res://client/sprites/pet-egg-pack/eggs/named/0619-spain.png",
	"Ocean": "res://client/sprites/pet-egg-pack/eggs/named/0564-photon-frost.png",
	"Forest": "res://client/sprites/pet-egg-pack/eggs/named/0579-toxic-confetti.png",
	"Dusk": "res://client/sprites/pet-egg-pack/eggs/named/0528-void-orchid.png",
	"Ember": "res://client/sprites/pet-egg-pack/eggs/named/0520-solar-flare.png",
	"Arctic": "res://client/sprites/pet-egg-pack/eggs/named/0624-egg-base.png",
	"Volcanic": "res://client/sprites/pet-egg-pack/eggs/named/0604-koi-arcade.png",
	"Twilight": "res://client/sprites/pet-egg-pack/eggs/named/0538-candy-nightshift.png",
	"Dawn": "res://client/sprites/pet-egg-pack/eggs/colorways/0428-orange-gold.png",
	"Depths": "res://client/sprites/pet-egg-pack/eggs/named/0614-quasar-ice.png",
	"Bloom": "res://client/sprites/pet-egg-pack/eggs/named/0555-jungle-static.png",
	"Rising": "res://client/sprites/pet-egg-pack/eggs/named/0597-garnet.png",
	"Core": "res://client/sprites/pet-egg-pack/eggs/named/0582-volcano-surf.png",
	"Heart": "res://client/sprites/pet-egg-pack/eggs/named/0547-event-horizon.png",
	"Soul": "res://client/sprites/pet-egg-pack/eggs/named/0465-twilight.png",
	"Nexus": "res://client/sprites/pet-egg-pack/eggs/named/0527-toxic-confetti.png",
	"Beacon": "res://client/sprites/pet-egg-pack/eggs/named/0553-jamaica.png",
	"Tiger": "res://client/sprites/pet-egg-pack/eggs/named/0574-spain.png",
	"Candy": "res://client/sprites/pet-egg-pack/eggs/colorways/0432-silver-pink.png",
	"Electric": "res://client/sprites/pet-egg-pack/eggs/named/0566-plasma-meadow.png",
	"Aquatic": "res://client/sprites/pet-egg-pack/eggs/colorways/0363-cyan-teal.png",
	"Regal": "res://client/sprites/pet-egg-pack/eggs/named/0522-spain.png",
	"Haunted": "res://client/sprites/pet-egg-pack/eggs/named/0535-aurora-heatwave.png",
	"Outlined": "res://client/sprites/pet-egg-pack/eggs/named/0523-starlit-opal.png",
	"Glowing": "res://client/sprites/pet-egg-pack/eggs/named/0499-jungle-static.png",
	"Burning": "res://client/sprites/pet-egg-pack/eggs/named/0500-koi-arcade.png",
	"Frozen": "res://client/sprites/pet-egg-pack/eggs/named/0620-starlit-opal.png",
	"Toxic Glow": "res://client/sprites/pet-egg-pack/eggs/named/0602-jamaica.png",
	"Slash": "res://client/sprites/pet-egg-pack/eggs/colorways/0204-orange-gold.png",
	"Lightning": "res://client/sprites/pet-egg-pack/eggs/named/0512-plasma-meadow.png",
	"Rift": "res://client/sprites/pet-egg-pack/eggs/colorways/0247-cyan-cream.png",
	"Shattered": "res://client/sprites/pet-egg-pack/eggs/named/0563-opal.png",
	"Ascendant": "res://client/sprites/pet-egg-pack/eggs/colorways/0192-yellow-cream.png",
	"Phoenix": "res://client/sprites/pet-egg-pack/eggs/named/0572-solar-flare.png",
	"Comet": "res://client/sprites/pet-egg-pack/eggs/colorways/0256-blue-cyan.png",
	"Crescent": "res://client/sprites/pet-egg-pack/eggs/named/0581-void-orchid.png",
	"Split": "res://client/sprites/pet-egg-pack/eggs/named/0615-ruby.png",
	"Duality": "res://client/sprites/pet-egg-pack/eggs/named/0575-starlit-opal.png",
	"Twilit": "res://client/sprites/pet-egg-pack/eggs/colorways/0230-pink-teal-cream-variant-2.png",
	"Balanced": "res://client/sprites/pet-egg-pack/eggs/colorways/0181-red-yellow.png",
	"Chimeric": "res://client/sprites/pet-egg-pack/eggs/named/0556-koi-arcade.png",
	"Mosaic": "res://client/sprites/pet-egg-pack/eggs/named/0538-candy-nightshift.png",
	"Harlequin": "res://client/sprites/pet-egg-pack/eggs/colorways/0180-red-gold.png",
	"Aura": "res://client/sprites/pet-egg-pack/eggs/named/0618-solar-slush.png",
	"Corona": "res://client/sprites/pet-egg-pack/eggs/named/0620-starlit-opal.png",
	"Eclipse": "res://client/sprites/pet-egg-pack/eggs/named/0577-topaz.png",
	"Barcode": "res://client/sprites/pet-egg-pack/eggs/named/0523-starlit-opal.png",
	"Zebra": "res://client/sprites/pet-egg-pack/eggs/named/0575-starlit-opal.png",
	"Neon Bars": "res://client/sprites/pet-egg-pack/eggs/named/0603-jungle-static.png",
	"Jailbird": "res://client/sprites/pet-egg-pack/eggs/named/0493-germany.png",
	"Layered": "res://client/sprites/pet-egg-pack/eggs/named/0576-supernova-gold.png",
	"Stratified": "res://client/sprites/pet-egg-pack/eggs/colorways/0425-purple-teal.png",
	"Sediment": "res://client/sprites/pet-egg-pack/eggs/colorways/0096-black-white.png",
	"Framed": "res://client/sprites/pet-egg-pack/eggs/named/0620-starlit-opal.png",
	"Gilded": "res://client/sprites/pet-egg-pack/eggs/named/0540-citrine.png",
	"Corrupted": "res://client/sprites/pet-egg-pack/eggs/named/0523-starlit-opal.png",
	"Marked": "res://client/sprites/pet-egg-pack/eggs/named/0624-egg-base.png",
	"Hex": "res://client/sprites/pet-egg-pack/eggs/named/0584-amethyst.png",
	"Branded": "res://client/sprites/pet-egg-pack/eggs/colorways/0273-orange-brown.png",
	"Tidal": "res://client/sprites/pet-egg-pack/eggs/named/0605-lagoon-glass-matte.png",
	"Ripple": "res://client/sprites/pet-egg-pack/eggs/named/0483-candy-nightshift.png",
	"Current": "res://client/sprites/pet-egg-pack/eggs/named/0595-emerald.png",
	"Mirage": "res://client/sprites/pet-egg-pack/eggs/colorways/0211-orange-cream.png",
	"Speckled": "res://client/sprites/pet-egg-pack/eggs/named/0575-starlit-opal.png",
	"Starry": "res://client/sprites/pet-egg-pack/eggs/named/0550-greece.png",
	"Freckled": "res://client/sprites/pet-egg-pack/eggs/named/0489-ember-gilt-matte.png",
	"Glittering": "res://client/sprites/pet-egg-pack/eggs/named/0596-event-horizon.png",
	"Spotted": "res://client/sprites/pet-egg-pack/eggs/named/0485-citrine.png",
	"Ringed": "res://client/sprites/pet-egg-pack/eggs/named/0519-sapphire.png",
	"Orbital": "res://client/sprites/pet-egg-pack/eggs/named/0533-aquamarine.png",
	"Halo": "res://client/sprites/pet-egg-pack/eggs/named/0624-egg-base.png",
	"Misty": "res://client/sprites/pet-egg-pack/eggs/named/0620-starlit-opal.png",
	"Smoky": "res://client/sprites/pet-egg-pack/eggs/colorways/0097-black-silver.png",
	"Dreamlike": "res://client/sprites/pet-egg-pack/eggs/colorways/0229-white-cream.png",
	"Fading": "res://client/sprites/pet-egg-pack/eggs/named/0564-photon-frost.png",
	"Shiny": "res://client/sprites/pet-egg-pack/eggs/colorways/0228-white-cream-variant-2.png",
	"Radiant": "res://client/sprites/pet-egg-pack/eggs/colorways/0187-yellow-white.png",
	"Blessed": "res://client/sprites/pet-egg-pack/eggs/named/0624-egg-base.png",
	"Starfall": "res://client/sprites/pet-egg-pack/eggs/named/0522-spain.png",
	"Spectral": "res://client/sprites/pet-egg-pack/eggs/colorways/0371-periwinkle-cream.png",
	"Ethereal": "res://client/sprites/pet-egg-pack/eggs/named/0508-opal.png",
	"Celestial": "res://client/sprites/pet-egg-pack/eggs/colorways/0192-yellow-cream.png",
	"Bifrost": "res://client/sprites/pet-egg-pack/eggs/colorways/0182-red-tan.png",
	"Prismatic": "res://client/sprites/pet-egg-pack/eggs/colorways/0382-blue-pink.png",
	"Void": "res://client/sprites/pet-egg-pack/eggs/named/0623-void-orchid.png",
	"Cosmic": "res://client/sprites/pet-egg-pack/eggs/named/0523-starlit-opal.png",
	"Divine": "res://client/sprites/pet-egg-pack/eggs/colorways/0228-white-cream-variant-2.png",
	"Eclipsed": "res://client/sprites/pet-egg-pack/eggs/named/0554-japan.png",
	"Wyrmgold": "res://client/sprites/pet-egg-pack/eggs/named/0526-topaz.png",
	"Abyssal": "res://client/sprites/pet-egg-pack/eggs/named/0478-aquamarine.png",
	"Emberwake": "res://client/sprites/pet-egg-pack/eggs/colorways/0232-red-gold.png",
	"Hoarfrost": "res://client/sprites/pet-egg-pack/eggs/colorways/0378-blue-white.png",
	"Nightbloom": "res://client/sprites/pet-egg-pack/eggs/named/0531-amethyst.png",
	"Stormglass": "res://client/sprites/pet-egg-pack/eggs/named/0459-robin.png",
	"Gravebloom": "res://client/sprites/pet-egg-pack/eggs/named/0591-citrine.png",
}


static func sprite_for(variant_name: String) -> String:
	"""The egg sprite for a variant, or "" when there is none (unknown or legacy variant)."""
	if variant_name == "":
		return ""
	var p: String = String(SPRITE_BY_VARIANT.get(variant_name, ""))
	if p == "" or not ResourceLoader.exists(p):
		return ""
	return p
