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
			+ "[color=#FFD700]── Bulk listing ──[/color] The big green [color=#88FF88]Sell / Bulk List ▾[/color] button (top-left of the panel) opens the listing menu. Each menu row carries a live count: `Bulk: All Equipment (14)`. Empty categories are greyed out so you know what's actually listable. Picking a bulk row shows a confirmation popup with the total valor before anything ships. Single-item paths (List from Inventory, List Materials, List Egg) live in the same menu.\n\n"
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
	# v0.9.568 — Help coverage sweep. Eight new topics covering combat,
	# loot reveal, PvP combat, gathering scratch-off, craft reveal, and the
	# Sanctuary's Mastery / Imprints / Atlas pages. Filling the gaps the
	# audit identified — every active player-facing system should have a
	# ? button explaining what it is and how to interact.
	"combat_scene": {
		"title": "[color=#FFD700]Combat[/color]",
		"body": (
			"Turn-based combat. You and any allies act first; monsters resolve after. Each turn you draw a [color=#FFD700]hand of 3 ability cards[/color] from your deck — pick one, or auto-attack for free.\n\n"
			+ "[color=#FFD700]── Hand of 3 ──[/color]\n"
			+ "  • 3 random cards drawn from your full deck each turn.\n"
			+ "  • Cards you don't play go to discard; deck reshuffles when empty.\n"
			+ "  • Cards show their [b]resource cost[/b], [b]damage type[/b], and [b]status effects[/b] (if any).\n"
			+ "  • [color=#9ACD32]Auto-attack[/color] is always free — useful when resources are dry.\n\n"
			+ "[color=#FFD700]── Resource costs ──[/color]\n"
			+ "Your class uses ONE primary resource for abilities:\n"
			+ "  • [color=#5C9DFF]Mana[/color] — Wizard, Sorcerer, Cleric, Druid (INT/WIS classes).\n"
			+ "  • [color=#FF8866]Stamina[/color] — Fighter, Barbarian, Paladin (STR/CON classes).\n"
			+ "  • [color=#FFEE55]Energy[/color] — Rogue, Ranger (DEX/WITS classes).\n"
			+ "Resources regen [color=#88FF88]every turn[/color] (faster outside combat). Hit zero and you're stuck on auto-attacks until they refill.\n\n"
			+ "[color=#FFD700]── Variable-cost abilities ──[/color]\n"
			+ "Some cards [b]scale[/b] with how much resource you spend (e.g., bigger fireball for more mana). Floor is ~30% of nominal so low-resource turns still have a viable play.\n\n"
			+ "[color=#FFD700]── Status effects ──[/color]\n"
			+ "  • [color=#FF6644]Burn / Bleed / Poison[/color] — damage-over-time, ticks on the affected actor's turn.\n"
			+ "  • [color=#5C9DFF]Freeze / Stun[/color] — target skips their next action.\n"
			+ "  • [color=#A335EE]Vulnerable / Weakened[/color] — incoming/outgoing damage modifiers.\n"
			+ "Status icons appear on the target's portrait. Hover for remaining duration + strength.\n\n"
			+ "[color=#FFD700]── Mastery (ability rank) ──[/color]\n"
			+ "Each ability you use accumulates uses → ranks up. Higher rank = more damage. R0 [color=#FF8888]Untrained[/color] hits at 80%; R6 [color=#88FFFF]Mythic[/color] hits at 145%. Rank thresholds: 10 / 50 / 250 / 1200 / 4000 / 10000 uses. See [color=#9ACD32]/abilities[/color] for your current ranks.\n\n"
			+ "[color=#FFD700]── Can't afford your abilities? ──[/color]\n"
			+ "If your resource pool is too small for the cards you draw, [b]upgrade gear[/b]:\n"
			+ "  • [color=#FFD700]Equipment[/color] is the main lever — armor, accessories, weapons all roll resource bonuses at higher tiers. Tier 5+ gear typically rolls +N max resource lines.\n"
			+ "  • [color=#88FF88]Sources[/color] — drops from monster kills (scratch-off), dungeon chests, crafting (specialty recipes), market listings, salvaging for materials → crafting.\n"
			+ "  • [color=#A335EE]Sanctuary upgrades[/color] — the [color=#FFAA66]Combat[/color] tab in Sanctuary boosts max resource pool account-wide. Spend Baddie Points (earned on death).\n"
			+ "  • [color=#9ACD32]Stat allocation[/color] — INT raises Mana, CON raises Stamina, DEX raises Energy. Spend points in /stats.\n"
			+ "  • [color=#FFD700]Consumables[/color] — Mana / Stamina potions and similar can be brought into combat (mapped via Settings → Combat Items).\n\n"
			+ "[color=#FFD700]── Flee / Item / Companion ──[/color]\n"
			+ "  • [b]Flee[/b] — chance-based escape, scales with Sanctuary Economy upgrade.\n"
			+ "  • [b]Item[/b] — use a mapped consumable.\n"
			+ "  • [b]Companion[/b] — your active pet acts alongside you (auto-targeted)."
		),
	},
	"combat_loot": {
		"title": "[color=#FFD700]Loot Reveal[/color]",
		"body": (
			"After winning a fight, the loot panel pops up with a [color=#FFD700]16-slot scratch-off grid[/color]. Click cells to reveal rewards — gold, items, materials, and the occasional surprise.\n\n"
			+ "[color=#FFD700]── How it works ──[/color]\n"
			+ "  • Total reveals = the monster's tier-scaled budget, [color=#88FF88]+1 per flock kill[/color] (group fights).\n"
			+ "  • Each click reveals one cell. Once you've used your reveals, remaining cells stay hidden and you move on.\n"
			+ "  • Rare drops (equipment, eggs, special consumables) are [color=#FFD700]pinned[/color] — they'll always appear within your reveal budget regardless of click order.\n"
			+ "  • Common drops (gold, materials) make up the bulk of the grid.\n\n"
			+ "[color=#FFD700]── Skipping ──\n"
			+ "Click [color=#88FF88]Skip Reveal[/color] (or toggle [b]Autoskip[/b]) to instantly take everything within your budget. Useful for grinding when you don't care about the click-by-click reveal. The toggle is persisted across sessions.\n\n"
			+ "[color=#FFD700]── Movement is blocked ──[/color]\n"
			+ "You can't move on the world map while the loot panel is open (v0.9.566). Close or autoskip to resume travel.\n\n"
			+ "[color=#FFD700]── Tiers & quality ──[/color]\n"
			+ "Higher-tier monsters drop higher-tier items + larger budgets. Apex-variant monsters have a chance at unique exclusive drops (Apex Sigil, Apex Crystal — see /admin or apex zones).\n\n"
			+ "[color=#888888]Loot is tracked per player in party combat — everyone gets a full personal reveal panel.[/color]"
		),
	},
	"pvp_combat": {
		"title": "[color=#FFD700]PvP Combat[/color]",
		"body": (
			"Player-versus-player turn-based duel (v0.9.563). Triggered when one player attacks another in a PvP-enabled zone, or via [color=#9ACD32]/duel[/color]. [color=#FF6688]No PvE deck or abilities here[/color] — V1 keeps it simple and accessible.\n\n"
			+ "[color=#FFD700]── Three actions per round ──[/color]\n"
			+ "  • [color=#FF8866]Attack[/color] — STR×2 + weapon damage, ±25% variance. Affected by opponent's DEF.\n"
			+ "  • [color=#5C9DFF]Special[/color] — max(INT, DEX)×3 + weapon/2, ±25% variance. Mostly ignores DEF — counter-play to stat-tanky opponents.\n"
			+ "  • [color=#88FF88]Defend[/color] — zero outgoing damage this round, halves incoming. Great for bait + recovery.\n\n"
			+ "[color=#FFD700]── Simultaneous reveal ──[/color]\n"
			+ "Both players pick an action in private, then both reveal at the same time. No turn-order advantage. Mind-game the matchup: Attack beats Special on raw damage; Special beats Attack on tanky targets; Defend trades initiative for safety.\n\n"
			+ "[color=#FFD700]── Round cap & HP ──[/color]\n"
			+ "  • [b]15 rounds max[/b] — if neither player is KO'd, higher remaining HP wins.\n"
			+ "  • [b]PvP HP starts at character max but caps at 2000[/b]. Prevents endgame-vs-newbie curb-stomps. Your real HP is unaffected by the PvP fight.\n\n"
			+ "[color=#FFD700]── KO consequences ──[/color]\n"
			+ "Loser drops a [color=#FFD700]sack[/color] (v0.9.557) the winner can loot. Any [color=#FFAA00]bounty[/color] (v0.9.556) on the loser pays out to the winner.\n\n"
			+ "[color=#FFD700]── Disconnect ──[/color]\n"
			+ "Mid-fight disconnect = forfeit. Don't expect to flee by Alt-F4.\n\n"
			+ "[color=#888888]/duel — consensual PvP, any zone — still uses the legacy instant dice-roll. The full turn-based scene only fires in PvP-enabled zones or via attack on a flagged player.[/color]"
		),
	},
	"scratch_off": {
		"title": "[color=#FFD700]Gathering Minigame[/color]",
		"body": (
			"Fishing, Mining, and Logging all use the same two-phase minigame.\n\n"
			+ "[color=#FFD700]── Phase 1: Wait ──[/color]\n"
			+ "A timer ticks before the prompt appears. [b]Don't press anything[/b] — pressing too early fails the catch. The wait phase varies; resist the urge.\n\n"
			+ "[color=#FFD700]── Phase 2: Reaction ──[/color]\n"
			+ "When the prompt appears, press the [color=#88FF88]correct key[/color] within the window. Hit = success → catch added to inventory. Miss = no catch. The window length depends on your skill level + tool quality.\n\n"
			+ "[color=#FFD700]── Tier scaling ──[/color]\n"
			+ "  • Mining has [b]9 tiers[/b], Logging [b]6 tiers[/b], Fishing scales similarly.\n"
			+ "  • Higher tiers = better materials but require multiple successful reactions per catch (T1-2: 1 hit, T3-5: 2 hits, T6+: 3 hits).\n"
			+ "  • Higher-tier ore / wood / fish spawn farther from origin or in specific biomes.\n\n"
			+ "[color=#FFD700]── Tools ──[/color]\n"
			+ "Better tools widen the reaction window. Tools drop in chests or craft at specialty stations.\n\n"
			+ "[color=#FFD700]── What you catch ──[/color]\n"
			+ "  • [color=#88FF88]Materials[/color] — crafting inputs (ore, wood, fish meat).\n"
			+ "  • [color=#FFD700]Rare drops[/color] — chance at consumables, runes, or even small XP/valor boosts.\n"
			+ "  • [b]Skill XP[/b] — each successful catch ranks up the relevant gathering skill.\n\n"
			+ "[color=#888888]Salvage materials for Salvage Essence + bonus material rolls. Visit a crafting station to turn raw materials into gear.[/color]"
		),
	},
	"craft_reveal": {
		"title": "[color=#FFD700]Craft Reveal & Boost[/color]",
		"body": (
			"After committing to a craft, the [color=#FFD700]Craft Reveal[/color] panel animates the result — quality rating, output stats, and any rare bonuses. Crafting outcomes have hidden variance; the reveal shows you what you actually got.\n\n"
			+ "[color=#FFD700]── Boost mechanic ──[/color]\n"
			+ "Before the reveal commits, you can spend extra resources to [color=#88FF88]Boost[/color]:\n"
			+ "  • [b]Boost cost[/b] = a chunk of extra materials (varies by recipe).\n"
			+ "  • [b]Boost effect[/b] = improves the quality roll significantly + can unlock affixes the unboosted roll can't reach.\n"
			+ "  • [color=#FF8888]No undo[/color] — once you Boost or Skip, the result is locked.\n\n"
			+ "[color=#FFD700]── Quality Rating ──[/color]\n"
			+ "Each craft gets a Quality Rating that scales the output's base stats. Higher rating = stronger gear. Driven by:\n"
			+ "  • Your skill level vs the recipe difficulty.\n"
			+ "  • Whether you Boosted.\n"
			+ "  • Random variance (small).\n\n"
			+ "[color=#FFD700]── Reveal animation ──[/color]\n"
			+ "The numbers count up to their final values. Click anywhere to skip the animation if you don't want to wait.\n\n"
			+ "[color=#888888]Crafted items get is_consumable / item_type tags automatically — they'll route correctly to inventory and market.[/color]"
		),
	},
	"mastery_page": {
		"title": "[color=#FFD700]Ability Mastery & Headstart[/color]",
		"body": (
			"Each ability you use accumulates [color=#FFD700]uses[/color] → ranks up → does more damage. This page lets you spend [color=#FF6600]Baddie Points[/color] to start your [b]next character[/b] with rank already in an ability.\n\n"
			+ "[color=#FFD700]── Ranks ──[/color]\n"
			+ "  • R0 [color=#FF8888]Untrained[/color] — 80% damage.\n"
			+ "  • R1 [color=#FFAA88]Novice[/color] — 90% (10 uses).\n"
			+ "  • R2 [color=#FFD700]Adept[/color] — 100% baseline (50 uses).\n"
			+ "  • R3 [color=#88FF88]Expert[/color] — 110% (250 uses).\n"
			+ "  • R4 [color=#0070DD]Master[/color] — 120% (1200 uses).\n"
			+ "  • R5 [color=#FF44FF]Legend[/color] — 130% (4000 uses).\n"
			+ "  • R6 [color=#88FFFF]Mythic[/color] — 145% (10000 uses).\n\n"
			+ "[color=#FFD700]── Records vs current ──[/color]\n"
			+ "Your [b]account ceiling[/b] (best ever) is what you can Headstart up to. Each row shows it as `recorded: R<n> <Rank>`. Even after permadeath, ceilings persist — that's the carrot.\n\n"
			+ "[color=#FFD700]── Headstart purchase ──[/color]\n"
			+ "  • Press [color=#9ACD32]1-5[/color] to cycle a row's queued rank: R0 → R1 → … → cap → R0 (refund).\n"
			+ "  • Each cycle step deducts the BP cost: R1 = 25, R2 = 100, R3 = 500 (cumulative 625 BP for full R3).\n"
			+ "  • Cap is R3. Ranks R4-R6 remain earnable through play — Headstart doesn't trivialize the long-tail ranks.\n\n"
			+ "[color=#FFD700]── How it lands ──[/color]\n"
			+ "Your queued headstarts apply when you create your NEXT character. They appear as starting ability_uses sufficient to reach the queued rank. Refund at any time before that character is created.\n\n"
			+ "[color=#FFD700]── Earning ranks faster ──[/color]\n"
			+ "Use the ability in combat. Tier-matched fights give richer use-credit per ability. Lower-tier farming is less efficient per minute but works for completionism."
		),
	},
	"imprints_page": {
		"title": "[color=#FFD700]Variant Imprints[/color]",
		"body": (
			"[color=#FFD700]Variant Imprints[/color] are companion-influenced upgrades to your abilities (v0.9.549). When you rank up an ability while a companion is active, the rank-up popup offers a 3rd choice: [color=#A335EE]✦ Imprint[/color] — a trait inherited from the companion that adds a permanent rider to that ability.\n\n"
			+ "[color=#FFD700]── How imprints stack ──[/color]\n"
			+ "  • Each ability holds up to [b]4 imprints[/b].\n"
			+ "  • Imprints are [color=#FFD700]account-level[/color] — they survive permadeath.\n"
			+ "  • Stacking the same trait twice intensifies its effect; stacking different traits gives you a hybrid loadout.\n\n"
			+ "[color=#FFD700]── Trait categories ──[/color]\n"
			+ "10 trait categories total, each mapped from a set of companion species' [b]active.effect[/b] field. Common traits:\n"
			+ "  • [color=#FF6644]Burn[/color] — adds burn damage-over-time\n"
			+ "  • [color=#5C9DFF]Freeze[/color] — chance to freeze on hit\n"
			+ "  • [color=#88FF88]Heal[/color] — heals you for a fraction of damage dealt\n"
			+ "  • [color=#A335EE]Vulnerable[/color] — marks target for bonus follow-up damage\n"
			+ "  • [b]…and 6 more[/b] — see this page for what your companions can imprint.\n\n"
			+ "[color=#FFD700]── How riders fire ──[/color]\n"
			+ "Imprint riders are applied centrally during ability resolution. The ability fires its primary effect, then each imprint rider triggers in order. Visible status icons appear on the target portrait when a rider hits.\n\n"
			+ "[color=#FFD700]── Building a loadout ──[/color]\n"
			+ "Pair companions whose active.effect matches the build you want. 53 companions are mapped to imprint traits — see the [b]Inspect[/b] view on any companion card for its trait. Rank-up popup respects whatever companion is active at that moment.\n\n"
			+ "[color=#888888]This page is read-only — to add imprints, you must rank up an ability with the right companion active.[/color]"
		),
	},
	# v0.9.569 — Help coverage continued. Six more topics covering nested
	# in-game-output screens that v0.9.568 didn't reach: settings + keybinds,
	# salvage, trade window, build mode, quest log, dungeon select.
	"settings_menu": {
		"title": "[color=#FFD700]Settings & Keybinds[/color]",
		"body": (
			"All client-side preferences live here. Open via [color=#9ACD32]/settings[/color] or the action bar.\n\n"
			+ "[color=#FFD700]── Audio ──[/color]\n"
			+ "  • [b]Master volume[/b] — overall slider.\n"
			+ "  • [b]Music / SFX[/b] — separate sliders so you can mute one without the other.\n"
			+ "  • [b]Ambient toggle[/b] — silences zone-ambient noise without touching SFX.\n\n"
			+ "[color=#FFD700]── Display ──[/color]\n"
			+ "  • [b]UI scale[/b] — separate multipliers for monster ASCII art, world map, chat text. Useful on high-DPI displays.\n"
			+ "  • [b]Map font size[/b] — adjust the world-map character grid.\n"
			+ "  • [b]Combat font size[/b] — adjust combat scene panel text.\n\n"
			+ "[color=#FFD700]── Keybinds ──[/color]\n"
			+ "Action bar has 10 slots, default-bound to: [color=#9ACD32]Space[/color] / [color=#9ACD32]Q[/color] / [color=#9ACD32]W[/color] / [color=#9ACD32]E[/color] / [color=#9ACD32]R[/color] / [color=#9ACD32]1[/color] / [color=#9ACD32]2[/color] / [color=#9ACD32]3[/color] / [color=#9ACD32]4[/color] / [color=#9ACD32]5[/color]. Rebind any slot via [b]Settings → Keybinds[/b], pick the slot to rebind, press the new key. The default scheme is designed around WASD movement — `R` is the contextual location action (Fish/Mine/Chop/Dungeon/Forge/Quests depending on current tile).\n\n"
			+ "[color=#FFD700]── Combat items ──[/color]\n"
			+ "Map consumables to combat slots so you can use them mid-fight via the action bar. Default 5 slots; assign via Settings → Combat Items.\n\n"
			+ "[color=#FFD700]── Quality of life ──[/color]\n"
			+ "  • [b]Autoskip loot reveal[/b] — when on, the post-combat scratch-off auto-flips your reveal budget instantly.\n"
			+ "  • [b]Chat timestamps[/b] — toggle the `[HH:MM]` prefix on chat lines.\n\n"
			+ "[color=#888888]Settings persist to user://keybinds.json + user://connection_settings.json — survive client updates.[/color]"
		),
	},
	"salvage_menu": {
		"title": "[color=#FFD700]Salvage[/color]",
		"body": (
			"Convert unwanted items into [color=#FFD700]Salvage Essence (ESS)[/color] + a chance at bonus materials. Open from Inventory → Salvage.\n\n"
			+ "[color=#FFD700]── How it works ──[/color]\n"
			+ "  • Pick an item from your inventory using [color=#9ACD32]1-5[/color] (or click).\n"
			+ "  • The salvage view shows the ESS yield + the bonus-mat odds for that specific item.\n"
			+ "  • Confirm to consume the item and credit your account with ESS.\n\n"
			+ "[color=#FFD700]── What to salvage ──[/color]\n"
			+ "  • [b]Duplicate equipment[/b] — most efficient ESS source.\n"
			+ "  • [b]Low-tier finds[/b] you've outgrown — early Tier 1-2 gear once you're at Tier 4+.\n"
			+ "  • [b]Equipment you can't equip[/b] — wrong class / wrong slot.\n"
			+ "  • [b]Not[/b]: anything you might want to bring home via Home Stone (Equipment) for a future character.\n\n"
			+ "[color=#FFD700]── Bonus material rolls ──[/color]\n"
			+ "Some salvage rolls drop their constituent materials (gem fragments, magic dust, refined metal). Higher-tier items roll more often. The exact value table lives in `drop_tables.gd` SALVAGE_VALUES — see the bonus-mat row on the salvage panel for the per-item odds.\n\n"
			+ "[color=#FFD700]── ESS uses ──[/color]\n"
			+ "Salvage Essence is a crafting material in its own right — required for high-tier recipes, especially specialty smithing. It's also a market-tradeable resource.\n\n"
			+ "[color=#888888]Salvaged items are gone forever — no undo. Double-check before confirming.[/color]"
		),
	},
	"trade_window": {
		"title": "[color=#FFD700]Trade Window[/color]",
		"body": (
			"Direct player-to-player trade. Initiate by bumping into another player and selecting [color=#88FFCC]Trade[/color] from the action bar, or via [color=#9ACD32]/trade <player>[/color].\n\n"
			+ "[color=#FFD700]── Tabs ──[/color]\n"
			+ "  • [color=#FFD700]Items[/color] — equipment, consumables, materials.\n"
			+ "  • [color=#FFD700]Companions[/color] — non-active, non-registered companions only.\n"
			+ "  • [color=#FFD700]Eggs[/color] — incubating eggs (frozen or active).\n\n"
			+ "[color=#FFD700]── How to add ──[/color]\n"
			+ "Click an item / companion / egg row on your side to add it to your offer. Click again to remove.\n\n"
			+ "[color=#FFD700]── Confirm step ──[/color]\n"
			+ "Trades use a [b]two-step confirm[/b]:\n"
			+ "  1. Both players click [color=#88FF88]Ready[/color] to lock their offer.\n"
			+ "  2. Both players click [color=#FFD700]Confirm[/color] AGAIN to finalize. If either side changes their offer between Ready and Confirm, both Readys reset.\n"
			+ "This prevents last-second swaps from completing without your awareness.\n\n"
			+ "[color=#FFD700]── Restrictions ──[/color]\n"
			+ "  • Active companions can't be traded — dismiss first.\n"
			+ "  • Registered (Sanctuary) companions can't be traded — they're account-bound.\n"
			+ "  • Soulbound equipment can't be traded.\n"
			+ "  • Valor can be added as part of either offer.\n\n"
			+ "[color=#888888]Cancel at any time before final confirm — both inventories are unchanged.[/color]"
		),
	},
	"build_mode": {
		"title": "[color=#FFD700]Build Mode[/color]",
		"body": (
			"Place structures from your inventory onto the world map. Used to construct enclosures (player posts), guard towers, decorations, and crafting stations.\n\n"
			+ "[color=#FFD700]── Flow ──[/color]\n"
			+ "  1. Open inventory → select a buildable item (walls, posts, structures).\n"
			+ "  2. Pick [color=#88FF88]Build[/color] — enters build mode showing direction prompts.\n"
			+ "  3. Press a direction key ([color=#9ACD32]W/A/S/D[/color] or arrow keys) — places the structure on the adjacent tile in that direction.\n"
			+ "  4. Press [color=#9ACD32]Esc[/color] or [color=#9ACD32]Q[/color] to cancel before placing.\n\n"
			+ "[color=#FFD700]── Demolish ──[/color]\n"
			+ "Same flow but pick [color=#FF8888]Demolish[/color] from the action bar. Direction selects which adjacent tile to clear. Refunds a portion of materials.\n\n"
			+ "[color=#FFD700]── Placement rules ──[/color]\n"
			+ "  • Must be inside your own enclosure (or a clan-shared one if you're a clan member).\n"
			+ "  • The very first signpost can be placed anywhere walkable — that's how you START a new post.\n"
			+ "  • Some structures are tile-blocking (walls, towers, large decorations); some are walkable (paths, low decorations).\n"
			+ "  • Specialty stations (Blacksmith, Healer, Trading Post, Companion Stable) require specific recipes + crafting skill thresholds.\n\n"
			+ "[color=#FFD700]── Settler bubble + decay ──[/color]\n"
			+ "Posts you've built reduce monster spawn tier in a radius around them (the [b]settler bubble[/b]). Towers + Guards extend the radius. Untouched posts decay (Inactive 7d → Abandoned 30d → Auto-reclaim 120d) — visit regularly to keep the bubble healthy. See the post status panel (bump the [color=#FFD700]P[/color] tile) for live bubble + decay state.\n\n"
			+ "[color=#888888]Build recipes unlock at Construction skill thresholds — see Crafting → Construction for what's available.[/color]"
		),
	},
	"quest_log": {
		"title": "[color=#FFD700]Quests[/color]",
		"body": (
			"Quest objectives, turn-ins, and rewards. Access via the quest board at any trading post (bump the [color=#9ACD32]Q[/color] tile) or via [color=#9ACD32]/quests[/color].\n\n"
			+ "[color=#FFD700]── Quest types ──[/color]\n"
			+ "  • [color=#88FF88]Gather[/color] — fish / mine / chop N of a resource.\n"
			+ "  • [color=#FFA500]Kill[/color] — slay N of a monster type / level range.\n"
			+ "  • [color=#A335EE]Boss[/color] — kill a specific named boss (often dungeon-tied).\n"
			+ "  • [color=#FF6600]⚠ Threat Bounty[/color] — clear a threatening dungeon to restore the post's safety.\n"
			+ "  • [color=#FFD700]Chain[/color] — multi-stage quest line (Pathfinder's Trial, etc.). Each stage rewards an item; completing the chain awards a title + bonus rewards.\n"
			+ "  • [color=#5C9DFF]Daily[/color] — refresh on server reset; smaller rewards but reliable.\n"
			+ "  • [color=#FF4488]Hotzone[/color] — temporary biome-bonus quest while a hotzone is active.\n\n"
			+ "[color=#FFD700]── Accepting + tracking ──[/color]\n"
			+ "From the quest board, press [color=#9ACD32]1-5[/color] to accept a quest. Accepted quests appear in your active list (max 5 concurrent — abandon one to take another). Progress ticks automatically as you fight / gather / explore.\n\n"
			+ "[color=#FFD700]── Turn-in ──[/color]\n"
			+ "Return to the quest board at the issuing post. Completed quests show a [color=#88FF88]✓ Turn In[/color] option. Most quest rewards = valor + XP; chain quests + threat bounties layer in equipment / consumables / titles.\n\n"
			+ "[color=#FFD700]── Abandoning ──[/color]\n"
			+ "From the active list, abandon a quest to free a slot. No penalty — but you lose progress on it.\n\n"
			+ "[color=#888888]Compass and threat-bounty hints point you to the right post / monster zone when a quest needs a specific location.[/color]"
		),
	},
	"dungeon_select": {
		"title": "[color=#FFD700]Dungeon Entry[/color]",
		"body": (
			"Walking onto a [color=#FFD700]D[/color] tile prompts a dungeon entry confirmation. Each dungeon has a monster theme, a recommended level, and a guaranteed boss.\n\n"
			+ "[color=#FFD700]── What you see ──[/color]\n"
			+ "  • [b]Name[/b] (e.g., Orc Stronghold) + monster type (all encounters share the boss's species).\n"
			+ "  • [b]Recommended level[/b] — your character's level vs the dungeon's `min_level`.\n"
			+ "  • [b]Floors[/b] — number of encounters before the boss.\n"
			+ "  • [b]Tier[/b] — drop quality / monster strength scaling.\n\n"
			+ "[color=#FFD700]── Underleveled warning ──[/color]\n"
			+ "If your level is below the recommended threshold, a [color=#FF8888]Level Warning[/color] appears with [color=#FF8888]Enter Anyway[/color] / [color=#88FF88]Cancel[/color]. The dungeon does NOT block you — but the monsters scale to the dungeon's level, not yours. Bring a party or come back stronger.\n\n"
			+ "[color=#FFD700]── Party dungeons ──[/color]\n"
			+ "If you're the party leader, entry creates a shared instance for all party members. Snake-formation movement; party combat for each encounter; party loot on the boss. Each member gets a guaranteed boss egg.\n\n"
			+ "[color=#FFD700]── Dying inside ──[/color]\n"
			+ "Death in a dungeon is still permadeath. Use Cloak (Lv 20+) to escape if a fight goes south. Solo / no-cloak deaths drop a sack at the death tile (apex-zone PvP rules apply for non-dungeon zones; in dungeon, the corpse cleans up on instance close).\n\n"
			+ "[color=#FFD700]── Threat-corridor dungeons ──[/color]\n"
			+ "A dungeon that spawns near a settled post marks the post as [color=#FF6600]⚠ Under Threat[/color] until cleared. Threatened posts charge +20% market markup; the threat bounty quest in the post's quest board awards a juicy bonus for clearing the specific dungeon.\n\n"
			+ "[color=#888888]Dungeons despawn 60s after completion. World map shows a fresh one spawned elsewhere within minutes.[/color]"
		),
	},
	"bounty_board": {
		"title": "[color=#FFD700]💰 Bounty Board[/color]",
		"body": (
			"Player-funded bounties (Audit #14 Slice E, v0.9.556). Post valor on another player's head — payable to whoever KOs them in an apex-zone PvP fight.\n\n"
			+ "[color=#FFD700]── Post a bounty ──[/color]\n"
			+ "Fill in the target's character name + amount of valor → press [color=#88FF88]Post Bounty[/color]. The valor leaves your balance immediately and locks as a bounty. Min posting: [color=#FFD700]50 valor[/color].\n\n"
			+ "[color=#FFD700]── Multiple postings stack ──[/color]\n"
			+ "Anyone can post a bounty on anyone else. Multiple postings on the same target stack — the board shows the sum. Each posting is paid out separately on KO.\n\n"
			+ "[color=#FFD700]── Drilling into a target ──[/color]\n"
			+ "Click [color=#88FFCC]› view postings[/color] (or press the row's number key 1-9) to see each individual posting on that target — poster name + amount per row. Useful for assessing who's gunning for whom.\n\n"
			+ "[color=#FFD700]── Cancel your postings ──[/color]\n"
			+ "From the drill-down view, click [color=#FF8888]Cancel ALL my postings on this target[/color] for a full refund. The server verifies poster identity — you can only cancel your own.\n\n"
			+ "[color=#FFD700]── Payout ──[/color]\n"
			+ "When the target is KO'd in an apex-zone PvP fight, all bounty postings on them pay out to the winner. Stacking bounties = a juicier reward for the eventual hunter.\n\n"
			+ "[color=#FFD700]── Chat fallback ──[/color]\n"
			+ "  • [color=#9ACD32]/bounty list[/color] — re-opens this panel.\n"
			+ "  • [color=#9ACD32]/bountyboard[/color] / [color=#9ACD32]/bb[/color] — same thing, shorter alias.\n"
			+ "  • [color=#9ACD32]/bounty post / on / cancel[/color] — legacy V1 commands, fully functional.\n\n"
			+ "[color=#888888]Target must be online to receive a bounty for the first time (so they know they're marked). Offline players that already have bounties still show on the board (offline) tag.[/color]"
		),
	},
	"mastery_atlas": {
		"title": "[color=#FFD700]Mastery Atlas[/color]",
		"body": (
			"The Mastery Atlas (v0.9.566) consolidates every ability your account has touched into one page. Read-only — no new server traffic, just a clearer view of where you stand.\n\n"
			+ "[color=#FFD700]── Four data sources per ability ──[/color]\n"
			+ "Each row joins:\n"
			+ "  • [color=#88FF88]Current[/color] — rank on this character (from ability_uses). Resets on permadeath.\n"
			+ "  • [color=#87CEEB]Best ever[/color] — account ceiling from mastery_records. Survives permadeath. The number you can headstart up to.\n"
			+ "  • [color=#FFD700]Imprints[/color] — variant imprints stacked on this ability (account-level). Up to 4 per ability.\n"
			+ "  • [color=#9ACD32]Headstart[/color] — what rank your NEXT character will start at (queued via the Mastery Headstart page).\n\n"
			+ "[color=#FFD700]── Sorting ──[/color]\n"
			+ "The page lists abilities sorted by name. Look for gaps between Current and Best Ever to spot abilities you haven't grinded yet this character.\n\n"
			+ "[color=#FFD700]── How to fill it ──[/color]\n"
			+ "Use abilities in combat. Each use ticks ability_uses; new account-ceiling records when you reach a higher rank than ever before; new imprints when you rank up with a companion active.\n\n"
			+ "[color=#FFD700]── Why it exists ──[/color]\n"
			+ "Before the Atlas, mastery records / imprints / headstarts each had their own page. The Atlas gives you one place to see your full ability investment at a glance — useful for planning the next headstart purchase or the next companion pairing.\n\n"
			+ "[color=#888888]See the Mastery Headstart page to spend Baddie Points. See the Imprint Atlas for the full trait breakdown per ability.[/color]"
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
