extends Control
class_name HelpPanel

# Audit #4 Slice 1A (v0.9.485) — reusable in-place help overlay. Distinct from
# TutorialHintPanel (which is a one-shot, server-pushed teaching modal): this
# panel is reopenable from any screen via a small Help button, drawing topic
# content from a static registry below. New screens add a `help_topic_key`
# and we expand this file as the help-button-everywhere UX rolls out.
#
# Usage:
#   var hp := HelpPanel.new()
#   add_child(hp)
#   hp.show_topic("companion_stable")
#
# Topics live in HELP_TOPICS below. Each entry is {title, body} BBCode strings.

signal dismissed

const HELP_TOPICS := {
	"companion_stable": {
		"title": "[color=#FFD700]Companion Stable[/color]",
		"body": (
			"A [color=#FFD700]Companion Stable[/color] (the magenta [color=#FF80FF]C[/color] tile at Tier 5+ trading posts, or a player-built one inside an enclosure) is a living link to your Sanctuary's companion storage. Bump the tile to open it.\n\n"
			+ "[color=#888888]Build your own:[/color] Construction skill 35 unlocks a [color=#FFD700]Companion Stable[/color] recipe (8 wooden plank + 4 iron ore + 2 heartwood + 2 arcane crystal + 3 magic dust). Place inside your own enclosure for Sanctuary access at your settlement.\n\n"
			+ "[color=#FFD700]MANAGE TAB[/color]\n"
			+ "[color=#A335EE]✦ Deposit[/color] — non-registered active companion → kennel. Frees a roster slot.\n"
			+ "[color=#A335EE]✦ Return to Slot[/color] — a [color=#FF80FF][REGISTERED][/color] companion goes back to its registered slot (still registered).\n"
			+ "[color=#A335EE]✦ Withdraw[/color] — pull a kennel companion into your roster.\n"
			+ "[color=#A335EE]✦ Check Out[/color] (v0.9.493) — pull a Sanctuary-registered companion onto your character as the new active. Closes the death-and-respawn detour. Requires no current active.\n\n"
			+ "[color=#FFD700]FUSE TAB[/color]\n"
			+ "Mid-character fusion. Four modes via the selector at the top:\n"
			+ "  • [color=#FFD700]Same Type[/color] — 3 of same monster type AND sub-tier → next sub-tier (max sub-tier 8).\n"
			+ "  • [color=#FF00FF]Mixed T9[/color] — 8 [b]T8.8[/b] companions (Tier 8, sub-tier 8) → random Tier 9 companion. The capstone fusion.\n"
			+ "  • [color=#FF66FF]Hybrid[/color] — 2 different monster types both sub-tier 5+, consumes 1 [color=#FFD700]Hybrid Catalyst[/color] → hybrid blend.\n"
			+ "  • [color=#FFAA66]Tier Ascend[/color] — 3 of same monster type AND same tier (any sub-tier), consumes 1 [color=#FFD700]Ascension Catalyst[/color] → same type at tier+1, sub-tier 1. Keeps your pet's identity while raising rank.\n"
			+ "Inputs can come from kennel OR registered slots in any mode. If any input is registered, the output is auto-registered (slot-preserving). Otherwise it goes to the kennel.\n\n"
			+ "[color=#FF8888]Notes[/color]:\n"
			+ "  • Deposit and registration are independent operations. Depositing never changes registration status.\n"
			+ "  • Registered companions that are currently your active companion are NOT fuseable — deposit them first (use 'Return to Slot') to make them available.\n"
			+ "  • Kennel must have space (upgrade at the Sanctuary if full)."
		),
	},
	"home_stone_companion": {
		"title": "[color=#FFD700]Home Stone (Companion) — Register vs Kennel[/color]",
		"body": (
			"You're holding a [color=#FFD700]Home Stone (Companion)[/color]. It binds your active companion to your Sanctuary — but [b]how[/b] it binds depends on your choice.\n\n"
			+ "[color=#00FF00]✦ REGISTER[/color] — death-resistant slot.\n"
			+ "  • Companion is locked into one of your account's [color=#FF80FF]Registered slots[/color] in the Sanctuary.\n"
			+ "  • [b]Survives permadeath.[/b] On character death, the companion's current state (XP, level, sub-tier) is saved.\n"
			+ "  • You can check it out as your active companion on any future character.\n"
			+ "  • Registered slots are limited (default 2; upgrade in Sanctuary). Use them for your [color=#FFD700]most valuable[/color] long-term companions.\n"
			+ "  • Cannot be directly fused while registered — deposit it back to its slot via a Companion Stable to make it a fusion input.\n\n"
			+ "[color=#A335EE]✦ KENNEL[/color] — bulk storage.\n"
			+ "  • Companion is dismissed from active and stored in the Sanctuary kennel.\n"
			+ "  • [b]NOT death-resistant.[/b] Kenneled companions are gone if you have no surviving registered slot when the character dies.\n"
			+ "  • Designed for [color=#FFD700]fusion inputs[/color] — stockpile candidates for combining at the Companion Stable's Fuse tab.\n"
			+ "  • Kennel capacity is much larger than registered slots (default 30; also upgradeable).\n\n"
			+ "[color=#87CEEB]Decision rule[/color]: If it's your main pet you want to keep across deaths → Register. If it's a stockpile companion you'll feed into fusion → Kennel."
		),
	},
	"companions_page": {
		"title": "[color=#FFD700]Companions Page[/color]",
		"body": (
			"Your active pet, your collected roster, and your Sanctuary-registered companions — all on one page.\n\n"
			+ "[color=#FFD700]Active Companion[/color] — the pet currently fighting alongside you. Shown at the top with full ability text + XP bar.\n\n"
			+ "[color=#FFD700]Sanctuary Registered[/color] (when present) — companions stored in your account's permadeath-resistant slots. Read-only here; manage at any Tier 5+ NPC [color=#A335EE]Companion Stable[/color] or the Sanctuary's K tile. The currently checked-out slot is dimmed and marked [color=#FFD700][CHECKED OUT][/color].\n\n"
			+ "[color=#FFD700]Roster[/color] — your collected (non-registered) companions. Left-click to activate; right-click for Inspect / Release.\n\n"
			+ "[color=#FFD700]── Card info ──[/color]\n"
			+ "  • [color=#FF80FF][REG][/color] — currently checked out from a Sanctuary slot.\n"
			+ "  • [color=#FF80FF][HYBRID×X][/color] — a Hybrid Fusion result; the X is the partner monster type.\n"
			+ "  • Color-coded rarity tag — variant tier from [color=#888888][C][/color] common up to [color=#FFD700][P][/color] prismatic.\n"
			+ "  • [b]T<n>.<m>[/b] — Tier <n>, sub-tier <m>. Sub-tier is the within-tier ladder (1-8). T9 is the cap.\n"
			+ "  • [color=#FFAA66]Veteran/Champion/Warlord/Tyrant/Apex[/color] prefix — appears on companions ascended via Tier Ascension Fusion. The prefix tells you how many tier-steps above the base species the companion has climbed.\n\n"
			+ "[color=#FFD700]── Aggro Roles ──[/color]\n"
			+ "Each companion has an Aggro value (0-100%) controlling how often enemies target it instead of you. Roles:\n"
			+ "  • [color=#FFD700]Tank[/color] (50%+) — Frontliner. Draws enemy attacks; designed to soak hits so your character stays safe.\n"
			+ "  • [color=#FFA500]Fighter[/color] (30-49%) — Engaged participant. Balances damage with attention drawn.\n"
			+ "  • [color=#FFFFFF]Default[/color] (20-29%) — Neutral. Targeted at the baseline rate.\n"
			+ "  • [color=#87CEEB]Evasive[/color] (<20%) — Backline. Rarely targeted; relies on positioning. Pair with a tank or your character.\n\n"
			+ "[color=#888888]Hover any card for a detail tooltip. Right-click for the full Inspect view (abilities, effective bonuses, role, art).[/color]"
		),
	},
	"inventory_page": {
		"title": "[color=#FFD700]Inventory[/color]",
		"body": (
			"Your character's carried items, equipment, and gathered materials.\n\n"
			+ "[color=#FFD700]── Filter chips ──[/color] Click the chips at the top to toggle category visibility. Hidden categories don't take up screen space; toggle them back on when you need them.\n\n"
			+ "[color=#FFD700]── Item rarity colors ──[/color]\n"
			+ "  • [color=#FFFFFF]Common[/color] (white) → [color=#1EFF00]Uncommon[/color] (green) → [color=#0070DD]Rare[/color] (blue) → [color=#A335EE]Epic[/color] (purple) → [color=#FF8000]Legendary[/color] (orange) → [color=#FFD700]Mythic[/color] (gold).\n\n"
			+ "[color=#FFD700]── Common actions ──[/color]\n"
			+ "  • [b]Left-click[/b] an item to bring up its actions (Equip / Use / Discard / etc.).\n"
			+ "  • [b]Hover[/b] for a detailed tooltip (stats, comparison to current gear, source for materials).\n"
			+ "  • [b]Salvage[/b] turns items into [color=#FFD700]Salvage Essence[/color] (ESS) + a chance at bonus materials. Use it on duplicates and low-tier finds.\n"
			+ "  • [b]Materials[/b] (gathered resources) live in their own group — use them as crafting inputs.\n\n"
			+ "[color=#FFD700]── Equipment comparison ──[/color]\n"
			+ "When you hover an equipable item the tooltip shows green/red deltas vs whatever's currently in that slot, including Sanctuary house bonuses (HP multipliers, resource max).\n\n"
			+ "[color=#FFD700]── Home Stones ──[/color]\n"
			+ "Special consumables (Egg / Supplies / Equipment / Companion) that send items to your Sanctuary — survive permadeath. Drop from Tier 4+ chests or buy at NPC posts (`/stones`).\n\n"
			+ "[color=#888888]Capacity is shown at the top right. Upgrade in Sanctuary → Storage tier for more slots.[/color]"
		),
	},
	"stats_page": {
		"title": "[color=#FFD700]Stats & Progression[/color]",
		"body": (
			"Your character's stats, racial passives, class passives, and the [color=#FFD700]Progression Vectors[/color] dashboard.\n\n"
			+ "[color=#FFD700]── Stat allocation ──[/color] You earn 1 stat point per level. Spend them on STR / CON / DEX / INT / WIS / WITS to taste. Sanctuary upgrades + race bonuses stack on top.\n\n"
			+ "[color=#FFD700]── Class + Race passives ──[/color] Named here with full effect text. Each class has a passive that defines its identity; each race has its own. Both are always-on; you don't need to activate them.\n\n"
			+ "[color=#FFD700]── Progression Vectors ──[/color] The dashboard names every track you're advancing:\n"
			+ "  • Character XP + level progression\n"
			+ "  • Stat-point bank (visible bank with current count + spend pointer to /stats)\n"
			+ "  • [color=#FFD700]Sanctuary upgrades[/color] + Baddie Points (account-level, survive permadeath)\n"
			+ "  • 10 [color=#FFD700]Job specialties[/color] with commit markers — you can only fully commit to one specialty per skill family\n"
			+ "  • [color=#FFD700]Bestiary[/color] — kills per monster type unlock entries\n"
			+ "  • [color=#FFD700]Compass[/color] — 3-tier post-discovery layered reveal (direction → distance → name)\n"
			+ "  • [color=#FFD700]Atlas[/color] — regions visited per account\n"
			+ "  • [color=#FFD700]Soul Gems[/color] — late-game crafting material progression\n"
			+ "  • [color=#FFD700]Titles[/color] — rank progression (Jarl → High King → Elder → Eternal)\n\n"
			+ "[color=#FFD700]── Why all in one place ──[/color] Players were missing systems they were already advancing. The dashboard makes every track visible at a glance, with the next milestone called out.\n\n"
			+ "[color=#888888]Type [color=#9ACD32]/stats[/color] to spend stat points, [color=#9ACD32]/status[/color] for this dashboard.[/color]"
		),
	},
	"crafting_page": {
		"title": "[color=#FFD700]Crafting[/color]",
		"body": (
			"Combine materials into equipment, consumables, structures, and ingredients. The crafting station shows up to [b]7 transparency layers[/b] before you commit so you know what you're getting.\n\n"
			+ "[color=#FFD700]── Specialty lock-in ──[/color] Each skill family (e.g., Blacksmithing) has multiple specialties (Weaponsmith / Armorer / etc.). When you reach skill 25 you commit to ONE specialty per family — that unlocks the specialist-only recipes. Switching specialties is expensive; choose carefully.\n\n"
			+ "[color=#FFD700]── The 7 transparency layers ──[/color]\n"
			+ "  1. [b]Materials needed[/b] — exact counts, highlighted red if you're short.\n"
			+ "  2. [b]Skill required[/b] vs your current skill — green if you can craft.\n"
			+ "  3. [b]Output preview[/b] — name + base stats of what you'll produce.\n"
			+ "  4. [b]Material sources[/b] — where each input drops/spawns (reverse-lookup map).\n"
			+ "  5. [b]Quality odds[/b] — your % chance per quality tier given current skill.\n"
			+ "  6. [b]Sell-value preview[/b] — market rolling-average price for the output.\n"
			+ "  7. [b]Skill progression preview[/b] — your next 3 locked recipes by skill_required + levels_away.\n\n"
			+ "[color=#FFD700]── Quality scaling ──[/color] Higher quality = better base stats on the output. Skill ratio (your skill vs recipe difficulty) drives the odds; higher skill = better odds at higher quality tiers.\n\n"
			+ "[color=#888888]Crafting skill levels via successful crafts at or near your current skill. Failed crafts return some materials.[/color]"
		),
	},
	"market_page": {
		"title": "[color=#FFD700]Market[/color]",
		"body": (
			"Player-driven economy at trading posts. List items for [color=#FFD700]Valor[/color] (the universal currency), buy other players' listings.\n\n"
			+ "[color=#FFD700]── How pricing works ──[/color]\n"
			+ "  • [color=#FFAA00]base_valor[/color] — what the seller receives immediately when listing.\n"
			+ "  • [color=#FFAA00]markup_price[/color] — what the buyer pays. Includes a supply/demand markup that grows with the listed quantity at this post per category.\n"
			+ "  • Difference is the [color=#FFAA00]post tax[/color] (revenue absorbed by the trading post).\n\n"
			+ "[color=#FFD700]── Categories ──[/color] Equipment, Companion Eggs, Consumables, Tools, Runes, Materials, Monster Parts. Items stack in browse view EXCEPT equipment, eggs, and tools (each unique).\n\n"
			+ "[color=#FFD700]── Bulk listing ──[/color] List all equipment / consumables+tools / materials in one click.\n\n"
			+ "[color=#FFD700]── Owner-post bonus (v0.9.509) ──[/color] List items at your OWN player post (any enclosure your account built) for a [color=#88FF88]+25% valor[/color] top-up paid directly to your balance. The listing's price for other players is unchanged — buyers pay the same as they would at an NPC post. Rewards investing in your own settlement.\n\n"
			+ "[color=#FFD700]── Network browse ──[/color] See listings from OTHER trading posts. To buy from another post, consume a [color=#FFD700]Travel Stone[/color] or physically travel there. Specialty + Threat-marked posts always require physical presence (geographic value preserved).\n\n"
			+ "[color=#FFD700]── My Listings ──[/color] Track what you've listed across the network. Sort by category, price (asc/desc), name, or level.\n\n"
			+ "[color=#888888]Valor balance shows top-right. Earn it from quests, monster drops, and listing items. Spend it on market buys, NPC vendors, Sanctuary upgrades (where applicable).[/color]"
		),
	},
	"sanctuary_page": {
		"title": "[color=#FFD700]Sanctuary[/color]",
		"body": (
			"Your account-level home that survives permadeath. Spend [color=#FF6600]Baddie Points[/color] (earned on character death) on permanent upgrades that buff every future character.\n\n"
			+ "[color=#FFD700]── 5 tabs ──[/color]\n"
			+ "  • [color=#88FF88]Storage[/color] — house storage, kennel, egg incubator, companion slots — all the bigger-bag upgrades.\n"
			+ "  • [color=#FF8888]Combat[/color] — HP / resource max / regen, defensive bonuses.\n"
			+ "  • [color=#FFAA66]Stats[/color] — stat bonuses (STR/CON/DEX/INT/WIS/WITS) that stack with racial + character points.\n"
			+ "  • [color=#87CEEB]Discovery[/color] — Bestiary, Compass, Atlas qualitative unlocks.\n"
			+ "  • [color=#FFD700]Economy[/color] — starting Valor, flee chance, gathering / XP bonuses.\n\n"
			+ "[color=#FFD700]── Visibility cues ──[/color]\n"
			+ "  • Tab strip shows a [color=#88FF88]+N[/color] badge for each tab containing affordable upgrades.\n"
			+ "  • Top-of-page summary shows total affordable across all tabs.\n"
			+ "  • Each row tags [color=#88FF88]✓ AFFORDABLE[/color] or [color=#FFD700]✦ MAX[/color] so you know what to spend on next.\n\n"
			+ "[color=#FFD700]── Walkable tiles ──[/color]\n"
			+ "  • [color=#FFD700]S[/color] Storage chest — items sent home via Home Stones.\n"
			+ "  • [color=#00FFFF]U[/color] Upgrades — opens this panel.\n"
			+ "  • [color=#A335EE]C[/color] Companion slots — registered companions (death-resistant).\n"
			+ "  • [color=#FF8800]K[/color] Companion Stable — unified kennel + fusion station (v0.9.497).\n"
			+ "  • [color=#FF6600]D[/color] Door — exit to character select / play.\n\n"
			+ "[color=#888888]Baddie Point formula: scales with character level + total XP at death. Higher-level deaths give more BP.[/color]"
		),
	},
	"clan_page": {
		"title": "[color=#FFD700]Clans[/color]",
		"body": (
			"A clan is a persistent player group with shared identity, chat tag, and a [color=#FFD700]vault[/color] for sharing items.\n\n"
			+ "[color=#FFD700]── Joining a clan ──[/color]\n"
			+ "  • [b]Create[/b] one yourself — sets you as the leader. Costs Valor.\n"
			+ "  • [b]Accept[/b] an invitation from another leader. Pending invites surface in the panel.\n\n"
			+ "[color=#FFD700]── Leader perks ──[/color]\n"
			+ "  • Invite / kick members (limited capacity per clan tier).\n"
			+ "  • Set the public description ([color=#9ACD32]/clandesc[/color] up to 240 chars).\n"
			+ "  • Set a short tagline / motto ([color=#9ACD32]/clanmotto[/color] up to 50 chars). Renders below the description on the clan panel.\n"
			+ "  • Set the clan's [color=#FFD700]banner color[/color] ([color=#9ACD32]/clancolor #RRGGBB[/color]). The [TAG] marker follows the color through chat, whispers, player list, and the panel.\n"
			+ "  • Disband the clan.\n\n"
			+ "[color=#FFD700]── Clan Vault ──[/color]\n"
			+ "Shared 30-slot inventory. Any member can deposit or withdraw. Open via the [b]Vault[/b] button on the clan panel, or the legacy [color=#9ACD32]/vault[/color] chat command. Auto-refreshes when another member acts.\n\n"
			+ "[color=#FFD700]── Chat & presence ──[/color]\n"
			+ "Your clan tag prefixes your name in chat, whispers, and the player list. Whisper a clanmate from anywhere in the world.\n"
			+ "  • [color=#9ACD32]/c <msg>[/color] — clan-channel chat ([color=#88FFCC][CLAN][/color] marker). Aliases [color=#9ACD32]/cc[/color], [color=#9ACD32]/clanchat[/color].\n"
			+ "  • [color=#9ACD32]/p <msg>[/color] — party-channel chat ([color=#FFAA66][PARTY][/color] marker). Aliases [color=#9ACD32]/pc[/color], [color=#9ACD32]/partychat[/color].\n"
			+ "  • [color=#9ACD32]/clist[/color] — compact roster of online clanmates with level + class. Aliases [color=#9ACD32]/clanlist[/color], [color=#9ACD32]/clanonline[/color].\n"
			+ "  • [color=#9ACD32]/afk[/color] [reason] — mark yourself away ([color=#FFAA66][AFK][/color] badge). Auto-clears on move or chat. Explicit clear: [color=#9ACD32]/back[/color].\n"
			+ "  • [color=#9ACD32]/mentor on[/color] (Lv 20+) — volunteer as a mentor (gold [color=#FFD700]★[/color]). [color=#9ACD32]/mentors[/color] lists who's around. [color=#FFD700]Party with a Lv < 10 player and the whole party earns +25%% XP on every kill.[/color]\n"
			+ "  • Whispers from Lv <10 players to Lv 20+ recipients render a [color=#FFD700][NEW Lv X][/color] tag.\n"
			+ "  • [color=#9ACD32]/friend add|accept|list|requests <user>[/color] — account-level friend graph. Shows online status + current character for each friend. [color=#9ACD32]/block <user>[/color] silences a user's whispers.\n\n"
			+ "[color=#FFD700]── Live indicators ──[/color]\n"
			+ "  • The clan roster shows a [color=#66FF66]●[/color] green dot on online members, [color=#666666]○[/color] gray on offline; orange [color=#FFAA66]●[/color] when a member is AFK.\n"
			+ "  • Header chip shows N online out of total members.\n"
			+ "  • Clan-mate login/logout broadcasts a subtle chat line so you notice when your crew shows up.\n\n"
			+ "[color=#888888]Banner color is account-wide; tag visibility is global so other players know your affiliation at a glance.[/color]"
		),
	},
	"bestiary_page": {
		"title": "[color=#FFD700]Bestiary[/color]",
		"body": (
			"Account-level ledger of monster kills. Earned via the [color=#FFD700]Bestiary[/color] Sanctuary upgrade (Discovery tab).\n\n"
			+ "[color=#FFD700]── Why it matters ──[/color] Different monster types unlock different lore + drops. The Bestiary tracks which monster types you've killed and at what cumulative count. Locked monsters appear as [color=#888888]???[/color] until you've fought one.\n\n"
			+ "[color=#FFD700]── How to fill it ──[/color] Every kill on a new monster type adds an entry. Subsequent kills tick up the count. Variants (Corrosive / Frenzied / Cursed / etc.) share the entry with their base species — they're the same monster ledger-wise.\n\n"
			+ "[color=#FFD700]── How it pairs with HP discovery ──[/color] The client's known-HP system separately tracks how much damage you've dealt killing each (monster + level) pair. Used to estimate monster HP on the bar. Independent from the Bestiary, but both grow with combat experience.\n\n"
			+ "[color=#FFD700]── Tier coverage ──[/color] Bestiary entries span all 9 monster tiers (T1 Lv 1-5 → T9 Lv 5001+). The display groups by tier so you can see your progression at a glance.\n\n"
			+ "[color=#888888]Account-level — survives permadeath. Visit your Sanctuary → Bestiary to view.[/color]"
		),
	},
	"ability_page": {
		"title": "[color=#FFD700]Combat Deck & Ability Mapping[/color]",
		"body": (
			"Each combat turn you draw a hand of 3 abilities from your deck. Spend resources (Mana / Stamina / Energy depending on class) to play them.\n\n"
			+ "[color=#FFD700]── Hand of 3 ──[/color]\n"
			+ "  • Draw 3 random abilities from your deck at the start of each turn.\n"
			+ "  • Discarded cards reshuffle when the deck runs empty.\n"
			+ "  • Pick the card that fits the moment, or auto-attack for free.\n\n"
			+ "[color=#FFD700]── Variable-cost abilities ──[/color]\n"
			+ "  • Some abilities scale with resources spent (more mana → bigger fireball). Floor is ~30% of nominal so even low-resource turns have a viable play.\n"
			+ "  • Damage / heal / buff effects scale with cost.\n\n"
			+ "[color=#FFD700]── Ability mapping ──[/color]\n"
			+ "  • Open via Settings → Abilities, or right-click an ability in the picker.\n"
			+ "  • Assign abilities to slots 1-5 for quick-play during combat. Slots auto-fill with your unlocked abilities; remap any time.\n\n"
			+ "[color=#FFD700]── Deck variants ──[/color]\n"
			+ "Some character builds unlock alternate deck cards (Forethought, Tactical Retreat, etc.) via class progression. These appear in the picker once unlocked.\n\n"
			+ "[color=#FFD700]── Off-affinity counters ──[/color]\n"
			+ "Universal counter cards (planned) will let any class deal with abilities outside its primary affinity. Coming in a future update.\n\n"
			+ "[color=#888888]Tap the ? on the combat panel mid-fight for context-sensitive ability info.[/color]"
		),
	},
	"fusion_overview": {
		"title": "[color=#FFD700]Fusion[/color]",
		"body": (
			"At the [color=#FFD700]Fusion Station[/color] in your Sanctuary (or a Companion Stable's Fuse tab), you can combine kennel companions in four ways:\n\n"
			+ "[color=#A335EE]✦ Same Type[/color] — 3 companions of the same monster type and the same sub-tier → 1 companion of the next sub-tier. Path to maxing within a tier.\n\n"
			+ "[color=#A335EE]✦ Mixed T9[/color] — 8 [b]T8.8[/b] companions (Tier 8, sub-tier 8). Types can differ. → 1 random Tier 9 companion. The capstone fusion.\n\n"
			+ "[color=#A335EE]✦ Hybrid[/color] — 2 companions of [b]different[/b] monster types, both at sub-tier 5+, plus 1 [color=#FFD700]Hybrid Catalyst[/color] → a hybrid companion that blends both parents' bonuses and inherits the second parent's threshold ability.\n\n"
			+ "[color=#A335EE]✦ Tier Ascend[/color] — 3 companions of the [b]same monster type and same tier[/b] (any sub-tier mix), plus 1 [color=#FFD700]Ascension Catalyst[/color] → 1 companion of the [b]same type at tier+1[/b], sub-tier 1. Lets you raise your favorite pet's rank without changing what it is.\n\n"
			+ "[color=#FFD700]Hybrid Catalysts[/color] drop from Tier 5+ dungeon chests. [color=#FFD700]Ascension Catalysts[/color] drop from Tier 6+ dungeon chests.\n\n"
			+ "[color=#87CEEB]Walk to a Companion Stable (Tier 5+ NPC posts) to deposit/withdraw without needing to die.[/color]"
		),
	},
	# Audit #15 v0.9.515 — three more help topics covering Fusion Panel, Kennel Panel,
	# and Post Status Panel. Continues the help-button-everywhere rollout started at
	# v0.9.485.
	"fusion_panel": {
		"title": "[color=#FFD700]Fusion Station[/color]",
		"body": (
			"The Fusion Station lets you combine companions in your kennel + registered slots to upgrade them. Four modes via the tabs at the top.\n\n"
			+ "[color=#FFD700]── Same Type ──[/color]\n"
			+ "Pick 3 companions of the same monster type AND the same sub-tier → 1 companion of the next sub-tier. Caps at sub-tier 8 within a tier. The bread-and-butter path to maxing a sub-tier ladder.\n\n"
			+ "[color=#FFD700]── Mixed T9 ──[/color]\n"
			+ "Select exactly 8 [b]Tier 8, sub-tier 8[/b] companions (types can differ) → 1 random Tier 9 companion. The capstone fusion — only available once you've ground all the way to T8.8 across enough species.\n\n"
			+ "[color=#FFD700]── Hybrid ──[/color]\n"
			+ "Select exactly 2 companions of [b]different[/b] monster types, both at sub-tier 5+. Consumes 1 [color=#FFD700]Hybrid Catalyst[/color] (drops from T5+ dungeon chests). Produces a hybrid that blends bonuses from both parents and inherits the second parent's threshold ability. Lets you fuse synergies across species.\n\n"
			+ "[color=#FFD700]── Tier Ascend ──[/color]\n"
			+ "Select 3 companions of the [b]same monster type AND same tier[/b] (any sub-tier mix). Consumes 1 [color=#FFD700]Ascension Catalyst[/color] (drops from T6+ dungeon chests). Produces 1 companion of the [b]same type at tier+1, sub-tier 1[/b]. Lets you keep your favorite pet's identity while climbing the tier ladder. Output gets a [color=#FFAA66]Veteran/Champion/Warlord/Tyrant/Apex[/color] prefix marking how many tier-steps you've climbed.\n\n"
			+ "[color=#FF8888]Notes[/color]:\n"
			+ "  • Inputs can come from the kennel OR registered slots.\n"
			+ "  • If ANY input is registered, the output is auto-registered (slot-preserving).\n"
			+ "  • Registered active companion can't be fused directly — use 'Return to Slot' on a Companion Stable first.\n"
			+ "  • Kennel must have free space for non-registered outputs (upgrade via the Sanctuary)."
		),
	},
	"kennel_panel": {
		"title": "[color=#FFD700]Companion Kennel[/color]",
		"body": (
			"The kennel is your Sanctuary's bulk companion storage — separate from the small Registered slot ladder. Designed for stockpiling [color=#FFD700]fusion inputs[/color].\n\n"
			+ "[color=#FFD700]── Card actions ──[/color]\n"
			+ "Right-click any card for actions:\n"
			+ "  • [color=#FFD700]Release[/color] — permanently delete the companion. Frees a kennel slot.\n"
			+ "  • [color=#FFD700]Register[/color] — move from kennel into a [color=#FF80FF]Registered slot[/color] (account-permadeath-resistant). Requires a free registered slot.\n\n"
			+ "[color=#FFD700]── Sorting ──[/color]\n"
			+ "Header buttons toggle the sort key (level / tier / sub-tier / variant / name / type) and ascending/descending order. Great for hunting same-tier or same-type groups for Tier Ascend / Same Type fusions.\n\n"
			+ "[color=#FFD700]── How to fill ──[/color]\n"
			+ "  • Bring an active companion to a [color=#FF80FF]Companion Stable[/color] (T5+ NPC posts or player-built) and Deposit it.\n"
			+ "  • Wild eggs hatched into kennel storage.\n"
			+ "  • Tier Ascend Fusion outputs (if no inputs were registered) land here.\n\n"
			+ "[color=#FFD700]── Capacity ──[/color]\n"
			+ "Default kennel capacity is 30. Upgrade via the Sanctuary's Companions tab (Kennel Capacity track) to push it to 500 at max upgrade.\n\n"
			+ "[color=#FF8888]Kenneled companions are NOT death-resistant.[/color] If you die without a surviving Registered slot, you lose them. For your main pet, use the Register slot instead."
		),
	},
	"clan_vault_panel": {
		"title": "[color=#FFD700]Clan Vault[/color]",
		"body": (
			"A shared inventory for your clan. Any clan member can deposit items and any clan member can withdraw — designed for distributing gear, materials, and consumables across the roster.\n\n"
			+ "[color=#FFD700]── Tabs ──[/color]\n"
			+ "  • [color=#FFD700]Vault[/color] — items currently stored. Each row has a [color=#88FF88]Withdraw[/color] button.\n"
			+ "  • [color=#FFD700]Deposit[/color] — your inventory, with a [color=#88FF88]Deposit[/color] button on each row.\n\n"
			+ "[color=#FFD700]── Capacity ──[/color]\n"
			+ "Default 30 slots, shared across the entire clan. Stackable items consolidate by item id; uniques (equipment, eggs, tools) take one slot each.\n\n"
			+ "[color=#FFD700]── Sync ──[/color]\n"
			+ "The vault auto-refreshes when another clan member deposits or withdraws while you have the panel open. No need to close and reopen to see fresh state.\n\n"
			+ "[color=#FFD700]── Chat fallback ──[/color]\n"
			+ "`/vault` lists the vault contents in chat; `/vaultdep <slot>` deposits an inventory slot; `/vaultwd <index>` withdraws a vault slot. Use these as power-user shortcuts.\n\n"
			+ "[color=#FF8888]Notes[/color]:\n"
			+ "  • Any clan member can withdraw — there is no leader-only / officer-only gating. Treat the vault as a shared trust pool.\n"
			+ "  • [b]Soulbound[/b] items can't be deposited.\n"
			+ "  • Capacity upgrades are coming in a future clan-storage tier; for now, manage what fits."
		),
	},
	"stones_panel": {
		"title": "[color=#FFD700]NPC Home Stone Vendor[/color]",
		"body": (
			"Home Stones are special consumables that move things into your [color=#FFD700]Sanctuary[/color] — surviving permadeath. Buy them here for Valor.\n\n"
			+ "[color=#FFD700]── Stone types ──[/color]\n"
			+ "  • [color=#A335EE]Egg[/color] (500 valor, cap 3) — sends one incubating egg to Sanctuary storage. Use when you're carrying a high-value egg you don't want to lose to a deathrun.\n"
			+ "  • [color=#9ACD32]Supplies[/color] (800 valor, cap 5) — sends up to 10 consumables to Sanctuary storage. Pre-stash potions / scrolls for your next character.\n"
			+ "  • [color=#FFD700]Equipment[/color] (1500 valor, cap 2) — sends one equipped item to Sanctuary storage. Best for irreplaceable gear (chest finds, crafted exotics).\n"
			+ "  • [color=#FF6347]Companion[/color] (3000 valor, cap 2) — [b]registers[/b] your active companion to a Sanctuary slot. Survives permadeath. The single most valuable purchase here for serious pet investment.\n\n"
			+ "[color=#FFD700]── Cap rules ──[/color]\n"
			+ "Caps are per-character lifetime purchase limits at this NPC. Once you hit a stone's cap, you cannot buy more of it on this character (the row disables). Stones drop in T4+ chests as a non-buy alternative.\n\n"
			+ "[color=#FFD700]── How to use ──[/color]\n"
			+ "After buying, the stone appears in your inventory. Use it from inventory to trigger the transfer. The Companion stone in particular opens a register-or-kennel choice modal.\n\n"
			+ "[color=#FF8888]Notes[/color]:\n"
			+ "  • You must be at an NPC trading post to see this vendor.\n"
			+ "  • Chat fallbacks: `/stones` (list) + `/buystone <type>` (purchase)."
		),
	},
	"post_status_panel": {
		"title": "[color=#FFD700]Post Status[/color]",
		"body": (
			"The status panel shows the live state of a player-built post — its settler bubble, guard force, threat exposure, and inactivity. Open it by bumping the [color=#FFD700]P[/color] post marker at the center of your settlement.\n\n"
			+ "[color=#FFD700]── Settler Bubble ──[/color]\n"
			+ "The radius around the post within which monster spawn tier is suppressed. Bigger bubble = safer immediate surroundings.\n"
			+ "  • Base radius = 12 tiles.\n"
			+ "  • [color=#FFD700]+2 tiles[/color] per [color=#C0C0C0]Guard[/color] within 40 tiles of the post center.\n"
			+ "  • [color=#FFD700]+4 tiles[/color] per Guard stationed inside a [color=#FFFFFF]Tower[/color].\n"
			+ "  • Max radius = 35 tiles. Unguarded posts collapse to the 12-tile minimum — a marker zone with little real suppression.\n\n"
			+ "[color=#FFD700]── Threat tags ──[/color]\n"
			+ "[color=#FF6600]⚠ Under Threat[/color] appears when a nearby dungeon is active. Threatened posts:\n"
			+ "  • Charge [color=#FF8888]+20% market markup[/color] for visitors.\n"
			+ "  • Apply [color=#FF8888]+50% service prices[/color] at the post's vendors.\n"
			+ "  • Bias monster spawns in the surrounding 80-tile corridor toward the dungeon's type.\n"
			+ "  • Lose [color=#FF8888]1 effective suppression[/color] on the settler bubble (spawn tier rises +1 in the bubble until threat clears).\n"
			+ "  • Inject a [color=#FF6600]⚠ THREAT BOUNTY[/color] quest into the post's quest board for the matching dungeon.\n"
			+ "Clear the threatening dungeon to remove the marker.\n\n"
			+ "[color=#FFD700]── Inactivity tags ──[/color]\n"
			+ "Tracked via `last_tended_at` — refreshes when the owner moves inside, builds/demolishes, or feeds guards. \n"
			+ "  • [color=#FFAA00]⚠ Inactive (7d)[/color] — owner hasn't touched the post in 7+ days. Settler bubble suppression weakens by [color=#FF8888]-1[/color].\n"
			+ "  • [color=#FF8888]⚠⚠ ABANDONED (30d)[/color] — owner hasn't touched the post in 30+ days. Suppression drops to [color=#FF8888]0[/color] — no protection at all.\n"
			+ "Both tags stack with threat erosion. Visit the post (move within its bubble) to reset the timer.\n\n"
			+ "[color=#FFD700]── Feed All ──[/color]\n"
			+ "The button at the bottom feeds all guards at this post in one tap. Guards need food to keep contributing to the bubble; check the per-guard rows above to see who's hungry."
		),
	},
}

var _root_panel: PanelContainer
var _title_label: RichTextLabel
var _body_label: RichTextLabel
var _close_button: Button


func _ready() -> void:
	# top_level=true so this overlay never perturbs sibling layout (v0.9.487
	# fix). Without it, a hidden modal can still shrink the map area via
	# nested CenterContainer+PRESET_FULL_RECT pressure on the parent.
	top_level = true
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layout()
	visible = false


func show_topic(topic_key: String) -> void:
	var topic = HELP_TOPICS.get(topic_key, null)
	if topic == null:
		# Fallback: render the key itself so missing topics are at least visible.
		_set_content("[color=#FF6644]Help topic missing[/color]", "No content registered for '%s'." % topic_key)
	else:
		_set_content(str(topic.get("title", "")), str(topic.get("body", "")))
	visible = true
	if _close_button:
		_close_button.grab_focus()


func _set_content(title_bb: String, body_bb: String) -> void:
	if _title_label:
		_title_label.clear()
		_title_label.append_text(title_bb)
	if _body_label:
		_body_label.clear()
		_body_label.append_text(body_bb)


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key = event.keycode
		if key == KEY_ESCAPE or key == KEY_ENTER or key == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			_on_close()


func _build_layout() -> void:
	# Dim backdrop.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	# CenterContainer for reliable on-screen centering (see v0.9.478 hotfix).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	_root_panel = PanelContainer.new()
	_root_panel.custom_minimum_size = Vector2(560, 0)

	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.08, 0.10, 0.16, 0.98)
	panel_sb.border_color = Color(0.53, 0.81, 0.92, 1.0)  # skyblue border — distinct from TutorialHintPanel's gold
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.content_margin_left = 22
	panel_sb.content_margin_right = 22
	panel_sb.content_margin_top = 18
	panel_sb.content_margin_bottom = 18
	_root_panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_root_panel.add_child(vbox)

	_title_label = RichTextLabel.new()
	_title_label.bbcode_enabled = true
	_title_label.fit_content = true
	_title_label.scroll_active = false
	_title_label.add_theme_font_size_override("normal_font_size", 18)
	_title_label.custom_minimum_size = Vector2(0, 26)
	vbox.add_child(_title_label)

	_body_label = RichTextLabel.new()
	_body_label.bbcode_enabled = true
	_body_label.fit_content = true
	_body_label.scroll_active = true
	_body_label.add_theme_font_size_override("normal_font_size", 14)
	_body_label.custom_minimum_size = Vector2(516, 280)
	vbox.add_child(_body_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	_close_button = Button.new()
	_close_button.text = "Close  (Esc / Enter)"
	_close_button.custom_minimum_size = Vector2(220, 32)
	_close_button.focus_mode = Control.FOCUS_ALL
	_close_button.pressed.connect(_on_close)
	btn_row.add_child(_close_button)


func _on_close() -> void:
	visible = false
	dismissed.emit()


static func make_help_button(topic_key: String, help_panel: HelpPanel) -> Button:
	"""Convenience: returns a small '?' Help button that opens help_panel
	on the given topic_key. Caller is responsible for adding to a layout."""
	var btn := Button.new()
	btn.text = "?  Help"
	btn.tooltip_text = "Open help for this screen"
	btn.custom_minimum_size = Vector2(72, 26)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func(): help_panel.show_topic(topic_key))
	return btn
