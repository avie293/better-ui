-- Clean Pal UI configuration
--
-- This file is copied to %LOCALAPPDATA%\Pal\Saved\Config\CleanPalUI.lua on first launch.
-- Edit that copy; it survives mod updates. Press the reload hotkey in game to apply changes
-- (changed hotkeys themselves take effect after restarting the game).
-- Delete it to get the defaults back.
--
-- Settings per element (all optional):
--   mode      "show", "hide" or "auto". "auto" only shows the element while it matters, e.g.
--             health after taking damage, hunger when low, the weapon after switching or shooting.
--             Elements without an auto signal treat "auto" like "show".
--   opacity   0.0 - 1.0
--   scale     1.0 = original size, scaled around the element's center
--   x, y      offset in pixels at 1080p (positive x = right, positive y = down)
--   tint      { r, g, b, a } multiplied with the original colors, 0.0 - 1.0
--   bar_color { r, g, b, a } fill color of the element's gauge (health, hunger, Pal health)
--   seconds   how long "auto" keeps the element visible after a change (default: auto_seconds)
--   below     "auto" threshold for gauges, 0.0 - 1.0 (shown while the gauge is below it)
--
-- Elements that are not listed in a preset keep their vanilla look.
-- Element ids: hud, compass, quest_tracker, quest_markers, player_health, hunger, stamina,
-- pal_party, weapon, key_hints, status_effects, time_of_day, temperature, status_points,
-- player_level, pal_experience, experience_reward, item_log, item_pickups, place_name,
-- partner_skill, pal_skill_hints, tutorial, debuff_notice, weight_notice, enemy_health,
-- crosshair, jetpack, damage_vignette, damage_numbers, enemy_markers

return {
    -- Preset that is active on first launch. The last used preset is remembered afterwards.
    preset = "clean",

    -- Order used by the "next preset" hotkey.
    preset_order = { "clean", "minimal", "vanilla", "custom" },

    -- Keys: F1 - F12, A - Z, ZERO - NINE, NUM_ZERO - NUM_NINE, INS, DEL, HOME, END, PAGE_UP, PAGE_DOWN.
    -- Modifiers: ctrl, shift, alt. Set key = "" to disable a hotkey.
    hotkeys = {
        next_preset = { key = "F7", ctrl = true },
        peek = { key = "F8", ctrl = true },
        reload = { key = "F6", ctrl = true },
    },

    -- "peek" shows the vanilla HUD for this many seconds. 0 = toggle on and off instead.
    peek_seconds = 5,

    -- Default time "auto" elements stay visible after a change.
    auto_seconds = 4,

    -- Fade duration when elements appear or disappear. 0 = instant.
    fade_seconds = 0.25,

    presets = {
        vanilla = {},

        clean = {
            compass = { opacity = 0.8 },
            quest_tracker = { opacity = 0.85, scale = 0.9 },
            player_health = { mode = "auto" },
            hunger = { mode = "auto", below = 0.5 },
            pal_party = { opacity = 0.9, scale = 0.9 },
            weapon = { mode = "auto" },
            key_hints = { mode = "hide" },
            pal_skill_hints = { mode = "hide" },
            time_of_day = { opacity = 0.8 },
            tutorial = { mode = "hide" },
        },

        minimal = {
            compass = { mode = "hide" },
            quest_tracker = { mode = "hide" },
            quest_markers = { opacity = 0.6 },
            player_health = { mode = "auto" },
            hunger = { mode = "auto", below = 0.3 },
            pal_party = { mode = "auto" },
            weapon = { mode = "auto", seconds = 3 },
            key_hints = { mode = "hide" },
            pal_skill_hints = { mode = "hide" },
            partner_skill = { mode = "hide" },
            time_of_day = { mode = "hide" },
            status_points = { mode = "hide" },
            player_level = { mode = "hide" },
            pal_experience = { mode = "hide" },
            experience_reward = { mode = "hide" },
            place_name = { mode = "hide" },
            tutorial = { mode = "hide" },
        },

        -- Starting point for your own layout.
        custom = {
            compass = { mode = "show", opacity = 1.0, scale = 1.0, x = 0, y = 0 },
            player_health = { mode = "auto", seconds = 5, bar_color = { 0.35, 0.85, 0.45, 1.0 } },
            weapon = { mode = "show", tint = { 1.0, 1.0, 1.0, 0.9 } },
        },
    },
}
