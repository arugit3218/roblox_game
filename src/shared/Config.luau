--!strict
-- Tunable gameplay values. NOTE: replicated to clients — nothing secret here,
-- and the server never trusts a client-reported value from this file.

return table.freeze({
	-- Content phase: limits which creature tiers / trails / speed levels exist.
	PHASE = 1,
	MAX_TIER = 5,

	-- Persistence
	AUTOSAVE_INTERVAL = 60,
	LOCK_STALE_SECONDS = 150,

	-- Idle
	OFFLINE_CAP_SECONDS = 12 * 60 * 60, -- aquarium stops accruing after 12h uncollected
	INCUBATOR_SLOTS = 8,
	AQUARIUM_SLOTS = 10,
	KITCHEN_SLOTS = 6,
	ORDER_SLOTS = 3,

	-- Movement / heist
	BASE_SPEED = 25,
	CATCH_DISTANCE = 4,
	CHASE_REACTION_DELAY = 0.6,
	CHASE_TIMEOUT = 60,
	ESCAPE_Z = 44, -- crossing below this Z line = safe
	STEAL_REACH = 14,
	HEIST_MAX_Y = 40, -- carrying an egg above this height fails the heist (anti-fly)
	EGG_REROLL_SECONDS = 30,

	-- Sleeping creatures: steal while asleep for a head start.
	SLEEP_SECONDS = { 10, 18 },
	AWAKE_SECONDS = { 8, 14 },
	SLEEP_BONUS_DELAY = 1.6,

	-- Server-wide "Golden Current" event: boosted variant luck + double heist coins.
	EVENT_INTERVAL = 10 * 60,
	EVENT_DURATION = 3 * 60,
	EVENT_LUCK = 3,
	EVENT_REWARD_MULT = 2,
})
