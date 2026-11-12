-- HUD elements that can be configured.
--
-- root:   class of the UserWidget the lookup starts from (the live instance is found by class).
-- path:   widget names resolved one after another with GetWidgetFromName. Every entry except
--         the last one must be a UserWidget, because the lookup only searches its own tree.
-- watch:  optional signals for the "auto" mode. The element is shown while a progress bar is
--         below its threshold, or for a few seconds after a watched value changed.

local PLAYER_UI = "WBP_PlayerUI_C"
local GAUGE = { "WBP_PlayerSideInfo_Separated", "WBP_Ingame_PlayerGauge_Separated" }

local function gauge(name)
    return { GAUGE[1], GAUGE[2], name }
end

return {
    {
        id = "hud",
        label = "Whole HUD",
        root = PLAYER_UI,
        path = {},
    },
    {
        id = "compass",
        label = "Compass",
        root = PLAYER_UI,
        path = { "WBP_Ingame_Compass" },
    },
    {
        id = "quest_tracker",
        label = "Quest and base camp tracker",
        root = PLAYER_UI,
        path = { "WBP_QuestAndBaseCampInfoCanvas" },
    },
    {
        id = "quest_markers",
        label = "Quest markers in the world",
        root = PLAYER_UI,
        path = { "WBP_QuestTrackingIconCanvas" },
    },
    {
        id = "player_health",
        label = "Player health and shield",
        root = PLAYER_UI,
        path = gauge("GaugeInfo"),
        watch = {
            { path = gauge("ProgressBar_HPGauge"), progress = true, below = 1.0 },
            { path = gauge("ProgressBar_ShieldGauge"), progress = true },
        },
    },
    {
        id = "hunger",
        label = "Hunger gauge",
        root = PLAYER_UI,
        path = gauge("WBP_IngameHungerGauge"),
        watch = {
            { path = { GAUGE[1], GAUGE[2], "WBP_IngameHungerGauge", "ProgressBar_219" }, progress = true, below = 0.5 },
        },
    },
    {
        id = "stamina",
        label = "Stamina circle",
        root = PLAYER_UI,
        path = { "WBP_Ingame_PlayerStamina_Circle" },
    },
    {
        id = "pal_party",
        label = "Pal party and active Pal health",
        root = PLAYER_UI,
        path = gauge("WBP_Ingame_PalHPGauge"),
        watch = {
            { path = { GAUGE[1], GAUGE[2], "WBP_Ingame_PalHPGauge", "ProgressBar_HPGauge" }, progress = true, below = 1.0 },
            { path = { GAUGE[1], GAUGE[2], "WBP_Ingame_PalHPGauge", "Text_PalName" }, text = true },
        },
    },
    {
        id = "weapon",
        label = "Weapon, ammo and spheres",
        root = PLAYER_UI,
        path = gauge("Canvas_WeaponInfo"),
        watch = {
            { path = gauge("Text_WeaponName"), text = true },
            { path = gauge("Text_NowBulletNum"), text = true },
            { path = gauge("Text_SphereName"), text = true },
        },
    },
    {
        id = "key_hints",
        label = "Key hints next to the weapon",
        root = PLAYER_UI,
        path = gauge("VerticalBox_CommonKeyGuide"),
    },
    {
        id = "status_effects",
        label = "Buff and debuff timers",
        root = PLAYER_UI,
        path = gauge("WBP_StatusBuffTimerContainer"),
    },
    {
        id = "time_of_day",
        label = "Time of day",
        root = PLAYER_UI,
        path = gauge("WBP_Ingame_TimeZone"),
    },
    {
        id = "temperature",
        label = "Temperature",
        root = PLAYER_UI,
        path = gauge("WBP_Ingame_Thermometer"),
    },
    {
        id = "status_points",
        label = "Unspent status points notice",
        root = PLAYER_UI,
        path = gauge("WBP_IngameStatusPoint"),
    },
    {
        id = "player_level",
        label = "Player level and experience",
        root = PLAYER_UI,
        path = { "WBP_PLLvExp" },
    },
    {
        id = "pal_experience",
        label = "Pal experience popups",
        root = PLAYER_UI,
        path = { "WBP_PalLvExp_List" },
    },
    {
        id = "experience_reward",
        label = "Experience reward popup",
        root = PLAYER_UI,
        path = { "WBP_CommonExpReward_ForDisplay" },
    },
    {
        id = "item_log",
        label = "Log messages",
        root = PLAYER_UI,
        path = { "WBP_PalLogWidget" },
    },
    {
        id = "item_pickups",
        label = "Picked up items",
        root = PLAYER_UI,
        path = { "WBP_PalIngameMenuItem_GetGroup" },
    },
    {
        id = "place_name",
        label = "Area name banner",
        root = PLAYER_UI,
        path = { "WBP_IngamePlaceName" },
    },
    {
        id = "partner_skill",
        label = "Partner skill",
        root = PLAYER_UI,
        path = { "WBP_PartnerSkillInfo" },
    },
    {
        id = "pal_skill_hints",
        label = "Pal skill key hints",
        root = PLAYER_UI,
        path = { "WBP_PalSkill_KeyGuide" },
    },
    {
        id = "tutorial",
        label = "Tutorial messages",
        root = PLAYER_UI,
        path = { "WBP_TutorialMessage_Temp" },
    },
    {
        id = "debuff_notice",
        label = "Debuff notices",
        root = PLAYER_UI,
        path = { "WBP_PalPlayerDebuffNoticeBox" },
    },
    {
        id = "weight_notice",
        label = "Overweight notice",
        root = PLAYER_UI,
        path = { "WBP_WeightNotice" },
    },
    {
        id = "enemy_health",
        label = "Health bars above Pals and NPCs",
        root = PLAYER_UI,
        path = { "WBP_PalNPCHPGaugeCanvas" },
    },
    {
        id = "crosshair",
        label = "Crosshair",
        root = PLAYER_UI,
        path = { "WBP_IngameSmesTop", "WBP_PalAim" },
    },
    {
        id = "jetpack",
        label = "Glider and jetpack gauge",
        root = PLAYER_UI,
        path = { "WBP_JetPackGauge" },
    },
    {
        id = "damage_vignette",
        label = "Red screen edge when hurt",
        root = PLAYER_UI,
        path = { "WBP_IngameDamageVinette" },
    },
    {
        id = "damage_numbers",
        label = "Damage numbers",
        root = "WBP_PalDamageCanvas_OneShotText_C",
        path = {},
    },
    {
        id = "enemy_markers",
        label = "Enemy alert markers",
        root = "WBP_EnemyMark_C",
        path = {},
    },
}
