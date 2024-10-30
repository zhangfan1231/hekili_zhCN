-- DeathKnightFrost.lua
-- July 2024

if UnitClassBase( "player" ) ~= "DEATHKNIGHT" then return end

local addon, ns = ...
local Hekili = _G[ addon ]
local class, state = Hekili.Class, Hekili.State

local PTR = ns.PTR

local strformat = string.format

local spec = Hekili:NewSpecialization( 251 )

spec:RegisterResource( Enum.PowerType.Runes, {
    rune_regen = {
        last = function ()
            return state.query_time
        end,

        interval = function( time, val )
            local r = state.runes
            val = math.floor( val )

            if val == 6 then return -1 end
            return r.expiry[ val + 1 ] - time
        end,

        stop = function( x )
            return x == 6
        end,

        value = 1
    },

    empower_rune = {
        aura = "empower_rune_weapon",

        last = function ()
            return state.buff.empower_rune_weapon.applied + floor( ( state.query_time - state.buff.empower_rune_weapon.applied ) / 5 ) * 5
        end,

        stop = function ( x )
            return x == 6
        end,

        interval = 5,
        value = 1
    },
}, setmetatable( {
    expiry = { 0, 0, 0, 0, 0, 0 },
    cooldown = 10,
    regen = 0,
    max = 6,
    forecast = {},
    fcount = 0,
    times = {},
    values = {},
    resource = "runes",

    reset = function()
        local t = state.runes

        for i = 1, 6 do
            local start, duration, ready = GetRuneCooldown( i )

            start = start or 0
            duration = duration or ( 10 * state.haste )

            t.expiry[ i ] = ready and 0 or start + duration
            t.cooldown = duration
        end

        table.sort( t.expiry )

        t.actual = nil
    end,

    gain = function( amount )
        local t = state.runes

        for i = 1, amount do
            t.expiry[ 7 - i ] = 0
        end
        table.sort( t.expiry )

        t.actual = nil
    end,

    spend = function( amount )
        local t = state.runes

        for i = 1, amount do
            t.expiry[ 1 ] = ( t.expiry[ 4 ] > 0 and t.expiry[ 4 ] or state.query_time ) + t.cooldown
            table.sort( t.expiry )
        end

        state.gain( amount * 10, "runic_power" )

        if state.talent.gathering_storm.enabled and state.buff.remorseless_winter.up then
            state.buff.remorseless_winter.expires = state.buff.remorseless_winter.expires + ( 0.5 * amount )
        end

        t.actual = nil
    end,

    timeTo = function( x )
        return state:TimeToResource( state.runes, x )
    end,
}, {
    __index = function( t, k, v )
        if k == "actual" then
            local amount = 0

            for i = 1, 6 do
                if t.expiry[ i ] <= state.query_time then
                    amount = amount + 1
                end
            end

            return amount

        elseif k == "current" then
            -- If this is a modeled resource, use our lookup system.
            if t.forecast and t.fcount > 0 then
                local q = state.query_time
                local index, slice

                if t.values[ q ] then return t.values[ q ] end

                for i = 1, t.fcount do
                    local v = t.forecast[ i ]
                    if v.t <= q then
                        index = i
                        slice = v
                    else
                        break
                    end
                end

                -- We have a slice.
                if index and slice then
                    t.values[ q ] = max( 0, min( t.max, slice.v ) )
                    return t.values[ q ]
                end
            end

            return t.actual

        elseif k == "deficit" then
            return t.max - t.current

        elseif k == "time_to_next" then
            return t[ "time_to_" .. t.current + 1 ]

        elseif k == "time_to_max" then
            return t.current == 6 and 0 or max( 0, t.expiry[6] - state.query_time )

        elseif k == "add" then
            return t.gain

        else
            local amount = k:match( "time_to_(%d+)" )
            amount = amount and tonumber( amount )

            if amount then return state:TimeToResource( t, amount ) end
        end
    end
} ) )

spec:RegisterResource( Enum.PowerType.RunicPower, {
    breath = {
        talent = "breath_of_sindragosa",
        aura = "breath_of_sindragosa",

        last = function ()
            return state.buff.breath_of_sindragosa.applied + floor( state.query_time - state.buff.breath_of_sindragosa.applied )
        end,

        stop = function ( x ) return x < 16 end,

        interval = 1,
        value = -16
    },

    empower_rp = {
        aura = "empower_rune_weapon",

        last = function ()
            return state.buff.empower_rune_weapon.applied + floor( ( state.query_time - state.buff.empower_rune_weapon.applied ) / 5 ) * 5
        end,

        interval = 5,
        value = 5
    },

    swarming_mist = {
        aura = "swarming_mist",

        last = function ()
            return state.buff.swarming_mist.applied + floor( state.query_time - state.buff.swarming_mist.applied )
        end,

        interval = 1,
        value = function () return min( 15, state.true_active_enemies * 3 ) end,
    },
} )

-- Talents
spec:RegisterTalents( {
    -- DeathKnight
    abomination_limb            = {  76049, 383269, 1 }, -- Sprout an additional limb, dealing 54,565 Shadow damage over 12 sec to all nearby enemies. Deals reduced damage beyond 5 targets. Every 1 sec, an enemy is pulled to your location if they are further than 8 yds from you. The same enemy can only be pulled once every 4 sec.
    antimagic_barrier           = {  76046, 205727, 1 }, -- Reduces the cooldown of Anti-Magic Shell by 20 sec and increases its duration and amount absorbed by 40%.
    antimagic_zone              = {  76065,  51052, 1 }, -- Places an Anti-Magic Zone that reduces spell damage taken by party or raid members by 20%. The Anti-Magic Zone lasts for 8 sec or until it absorbs 1.3 million damage.
    asphyxiate                  = {  76064, 221562, 1 }, -- Lifts the enemy target off the ground, crushing their throat with dark energy and stunning them for 5 sec.
    assimilation                = {  76048, 374383, 1 }, -- The amount absorbed by Anti-Magic Zone is increased by 10% and its cooldown is reduced by 30 sec.
    blinding_sleet              = {  76044, 207167, 1 }, -- Targets in a cone in front of you are blinded, causing them to wander disoriented for 5 sec. Damage may cancel the effect. When Blinding Sleet ends, enemies are slowed by 50% for 6 sec.
    blood_draw                  = {  76056, 374598, 1 }, -- When you fall below 30% health you drain 17,735 health from nearby enemies, the damage you take is reduced by 10% and your Death Strike cost is reduced by 10 for 8 sec. Can only occur every 2 min.
    blood_scent                 = {  76078, 374030, 1 }, -- Increases Leech by 3%.
    brittle                     = {  76061, 374504, 1 }, -- Your diseases have a chance to weaken your enemy causing your attacks against them to deal 6% increased damage for 5 sec.
    cleaving_strikes            = {  76073, 316916, 1 }, -- Obliterate hits up to 2 additional enemies while you remain in Death and Decay. When leaving your Death and Decay you retain its bonus effects for 4 sec.
    coldthirst                  = {  76083, 378848, 1 }, -- Successfully interrupting an enemy with Mind Freeze grants 10 Runic Power and reduces its cooldown by 3 sec.
    control_undead              = {  76059, 111673, 1 }, -- Dominates the target undead creature up to level 71, forcing it to do your bidding for 5 min.
    death_pact                  = {  76075,  48743, 1 }, -- Create a death pact that heals you for 50% of your maximum health, but absorbs incoming healing equal to 30% of your max health for 15 sec.
    death_strike                = {  76071,  49998, 1 }, -- Focuses dark power into a strike with both weapons, that deals a total of 8,500 Physical damage and heals you for 40.00% of all damage taken in the last 5 sec, minimum 11.2% of maximum health.
    deaths_echo                 = { 102007, 356367, 1 }, -- Death's Advance, Death and Decay, and Death Grip have 1 additional charge.
    deaths_reach                = { 102006, 276079, 1 }, -- Increases the range of Death Grip by 10 yds. Killing an enemy that yields experience or honor resets the cooldown of Death Grip.
    enfeeble                    = {  76060, 392566, 1 }, -- Your ghoul's attacks have a chance to apply Enfeeble, reducing the enemies movement speed by 30% and the damage they deal to you by 12% for 6 sec.
    gloom_ward                  = {  76052, 391571, 1 }, -- Absorbs are 15% more effective on you.
    grip_of_the_dead            = {  76057, 273952, 1 }, -- Death and Decay reduces the movement speed of enemies within its area by 90%, decaying by 10% every sec.
    ice_prison                  = {  76086, 454786, 1 }, -- Chains of Ice now also roots enemies for 4 sec but its cooldown is increased to 12 sec.
    icebound_fortitude          = {  76081,  48792, 1 }, -- Your blood freezes, granting immunity to Stun effects and reducing all damage you take by 30% for 8 sec.
    icy_talons                  = {  76085, 194878, 1 }, -- Your Runic Power spending abilities increase your melee attack speed by 6% for 10 sec, stacking up to 5 times.
    improved_death_strike       = {  76067, 374277, 1 }, -- Death Strike's cost is reduced by 10, and its healing is increased by 60%.
    insidious_chill             = {  76051, 391566, 1 }, -- Your auto-attacks reduce the target's auto-attack speed by 5% for 30 sec, stacking up to 4 times.
    march_of_darkness           = {  76074, 391546, 1 }, -- Death's Advance grants an additional 25% movement speed over the first 3 sec.
    mind_freeze                 = {  76084,  47528, 1 }, -- Smash the target's mind with cold, interrupting spellcasting and preventing any spell in that school from being cast for 3 sec.
    null_magic                  = { 102008, 454842, 1 }, -- Magic damage taken is reduced by 8% and the duration of harmful Magic effects against you are reduced by 35%.
    osmosis                     = {  76088, 454835, 1 }, -- Anti-Magic Shell increases healing received by 15%.
    permafrost                  = {  76066, 207200, 1 }, -- Your auto attack damage grants you an absorb shield equal to 40% of the damage dealt.
    proliferating_chill         = { 101708, 373930, 1 }, -- Chains of Ice affects 1 additional nearby enemy.
    raise_dead                  = {  76072,  46585, 1 }, -- Raises a ghoul to fight by your side. You can have a maximum of one ghoul at a time. Lasts 1 min.
    rune_mastery                = {  76079, 374574, 2 }, -- Consuming a Rune has a chance to increase your Strength by 3% for 8 sec.
    runic_attenuation           = {  76045, 207104, 1 }, -- Auto attacks have a chance to generate 3 Runic Power.
    runic_protection            = {  76055, 454788, 1 }, -- Your chance to be critically struck is reduced by 3% and your Armor is increased by 6%.
    sacrificial_pact            = {  76060, 327574, 1 }, -- Sacrifice your ghoul to deal 11,084 Shadow damage to all nearby enemies and heal for 25% of your maximum health. Deals reduced damage beyond 8 targets.
    soul_reaper                 = {  76063, 343294, 1 }, -- Strike an enemy for 9,914 Shadowfrost damage and afflict the enemy with Soul Reaper. After 5 sec, if the target is below 35% health this effect will explode dealing an additional 45,489 Shadowfrost damage to the target. If the enemy that yields experience or honor dies while afflicted by Soul Reaper, gain Runic Corruption.
    subduing_grasp              = {  76080, 454822, 1 }, -- When you pull an enemy, the damage they deal to you is reduced by 6% for 6 sec.
    suppression                 = {  76087, 374049, 1 }, -- Damage taken from area of effect attacks reduced by 3%. When suffering a loss of control effect, this bonus is increased by an additional 6% for 6 sec.
    unholy_bond                 = {  76076, 374261, 1 }, -- Increases the effectiveness of your Runeforge effects by 20%.
    unholy_endurance            = {  76058, 389682, 1 }, -- Increases Lichborne duration by 2 sec and while active damage taken is reduced by 15%.
    unholy_ground               = {  76069, 374265, 1 }, -- Gain 5% Haste while you remain within your Death and Decay.
    unyielding_will             = {  76050, 457574, 1 }, -- Anti-Magic shell now removes all harmful magical effects when activated, but it's cooldown is increased by 20 sec.
    vestigial_shell             = {  76053, 454851, 1 }, -- Casting Anti-Magic Shell grants 2 nearby allies a Lesser Anti-Magic Shell that Absorbs up to 55,050 magic damage and reduces the duration of harmful Magic effects against them by 50%.
    veteran_of_the_third_war    = {  76068,  48263, 1 }, -- Stamina increased by 20%.
    will_of_the_necropolis      = {  76054, 206967, 2 }, -- Damage taken below 30% Health is reduced by 20%.
    wraith_walk                 = {  76077, 212552, 1 }, -- Embrace the power of the Shadowlands, removing all root effects and increasing your movement speed by 70% for 4 sec. Taking any action cancels the effect. While active, your movement speed cannot be reduced below 170%.

    -- Deathbringer
    absolute_zero               = { 102009, 377047, 1 }, -- Frostwyrm's Fury has 50% reduced cooldown and Freezes all enemies hit for 3 sec.
    arctic_assault              = {  76091, 456230, 1 }, -- Consuming Killing Machine fires a Glacial Advance through your target at 80% effectiveness.
    avalanche                   = {  76105, 207142, 1 }, -- Casting Howling Blast with Rime active causes jagged icicles to fall on enemies nearby your target, applying Razorice and dealing 4,963 Frost damage.
    biting_cold                 = {  76111, 377056, 1 }, -- Remorseless Winter damage is increased by 35%. The first time Remorseless Winter deals damage to 3 different enemies, you gain Rime.
    bonegrinder                 = {  76122, 377098, 2 }, -- Consuming Killing Machine grants 1% critical strike chance for 10 sec, stacking up to 5 times. At 5 stacks your next Killing Machine consumes the stacks and grants you 10% increased Frost damage for 10 sec.
    breath_of_sindragosa        = {  76093, 152279, 1 }, -- Continuously deal 25,472 Frost damage every 1 sec to enemies in a cone in front of you, until your Runic Power is exhausted. Deals reduced damage to secondary targets. Generates 2 Runes at the start and end.
    chill_streak                = {  76098, 305392, 1 }, -- Deals 25,420 Frost damage to the target and reduces their movement speed by 70% for 4 sec. Chill Streak bounces up to 12 times between closest targets within 10 yards.
    cold_heart                  = {  76035, 281208, 1 }, -- Every 2 sec, gain a stack of Cold Heart, causing your next Chains of Ice to deal 2,481 Frost damage. Stacks up to 20 times.
    cryogenic_chamber           = {  76109, 456237, 1 }, -- Each time Frost Fever deals damage, 15% of the damage dealt is gathered into the next cast of Remorseless Winter, up to 20 times.
    empower_rune_weapon         = {  76110,  47568, 1 }, -- Empower your rune weapon, gaining 15% Haste and generating 1 Rune and 5 Runic Power instantly and every 5 sec for 20 sec.
    enduring_chill              = {  76097, 377376, 1 }, -- Chill Streak's bounce range is increased by 2 yds and each time Chill Streak bounces it has a 25% chance to increase the maximum number of bounces by 1.
    enduring_strength           = {  76100, 377190, 1 }, -- When Pillar of Frost expires, your Strength is increased by 15% for 6 sec. This effect lasts 2 sec longer for each Obliterate and Frostscythe critical strike during Pillar of Frost.
    everfrost                   = {  76113, 376938, 1 }, -- Remorseless Winter deals 6% increased damage to enemies it hits, stacking up to 10 times.
    frigid_executioner          = {  76120, 377073, 1 }, -- Obliterate deals 15% increased damage and has a 15% chance to refund 2 runes.
    frost_strike                = {  76115,  49143, 1 }, -- Chill your weapon with icy power and quickly strike the enemy, dealing 26,260 Frost damage.
    frostscythe                 = {  76096, 207230, 1 }, -- A sweeping attack that strikes all enemies in front of you for 18,880 Frost damage. This attack always critically strikes and critical strikes with Frostscythe deal 4 times normal damage. Deals reduced damage beyond 5 targets. Consuming Killing Machine reduces the cooldown of Frostscythe by 1.0 sec.
    frostwhelps_aid             = {  76106, 377226, 1 }, -- Pillar of Frost summons a Frostwhelp who breathes on all enemies within 40 yards in front of you for 9,278 Frost damage. Each unique enemy hit by Frostwhelp's Aid grants you 8% Mastery for 15 sec, up to 40%.
    frostwyrms_fury             = { 101931, 279302, 1 }, -- Summons a frostwyrm who breathes on all enemies within 40 yd in front of you, dealing 81,901 Frost damage and slowing movement speed by 50% for 10 sec.
    gathering_storm             = {  76099, 194912, 1 }, -- Each Rune spent during Remorseless Winter increases its damage by 10%, and extends its duration by 0.5 sec.
    glacial_advance             = {  76092, 194913, 1 }, -- Summon glacial spikes from the ground that advance forward, each dealing 10,985 Frost damage and applying Razorice to enemies near their eruption point.
    horn_of_winter              = {  76089,  57330, 1 }, -- Blow the Horn of Winter, gaining 2 Runes and generating 25 Runic Power.
    howling_blast               = {  76114,  49184, 1 }, -- Blast the target with a frigid wind, dealing 4,770 Frost damage to that foe, and reduced damage to all other enemies within 10 yards, infecting all targets with Frost Fever.  Frost Fever A disease that deals 57,047 Frost damage over 24 sec and has a chance to grant the Death Knight 5 Runic Power each time it deals damage.
    hyperpyrexia                = {  76108, 456238, 1 }, -- Your Runic Power spending abilities have a chance to additionally deal 45% of the damage dealt over 4 sec.
    icebreaker                  = {  76033, 392950, 2 }, -- When empowered by Rime, Howling Blast deals 30% increased damage to your primary target.
    icecap                      = { 101930, 207126, 1 }, -- Reduces Pillar of Frost cooldown by 15 sec.
    icy_death_torrent           = { 101933, 435010, 1 }, -- Your auto attack critical strikes have a chance to send out a torrent of ice dealing 24,555 Frost damage to enemies in front of you.
    improved_frost_strike       = {  76103, 316803, 2 }, -- Increases Frost Strike damage by 10%.
    improved_obliterate         = {  76119, 317198, 1 }, -- Increases Obliterate damage by 10%.
    improved_rime               = {  76112, 316838, 1 }, -- Increases Howling Blast damage done by an additional 75%.
    inexorable_assault          = {  76037, 253593, 1 }, -- Gain Inexorable Assault every 8 sec, stacking up to 5 times. Obliterate consumes a stack to deal an additional 5,815 Frost damage.
    killing_machine             = {  76117,  51128, 1 }, -- Your auto attack critical strikes have a chance to make your next Obliterate deal Frost damage and critically strike.
    murderous_efficiency        = {  76121, 207061, 1 }, -- Consuming the Killing Machine effect has a 25% chance to grant you 1 Rune.
    obliterate                  = {  76116,  49020, 1 }, -- A brutal attack that deals 28,347 Physical damage.
    obliteration                = {  76123, 281238, 1 }, -- While Pillar of Frost is active, Frost Strike Soul Reaper, and Howling Blast always grant Killing Machine and have a 30% chance to generate a Rune. to deal additional damage.
    piercing_chill              = {  76097, 377351, 1 }, -- Enemies suffer 12% increased damage from Chill Streak each time they are struck by it.
    pillar_of_frost             = { 101929,  51271, 1 }, -- The power of frost increases your Strength by 30% for 12 sec.
    rage_of_the_frozen_champion = {  76120, 377076, 1 }, -- Obliterate has a 15% increased chance to trigger Rime and Howling Blast generates 6 Runic Power while Rime is active.
    runic_command               = {  76102, 376251, 2 }, -- Increases your maximum Runic Power by 5.
    shattered_frost             = {  76094, 455993, 1 }, -- When Frost Strike consumes 5 Razorice stacks, it deals 60% of the damage dealt to nearby enemies. Deals reduced damage beyond 8 targets.
    shattering_blade            = {  76095, 207057, 1 }, -- When Frost Strike damages an enemy with 5 stacks of Razorice it will consume them to deal an additional 115% damage.
    smothering_offense          = {  76101, 435005, 1 }, -- Your auto attack damage is increased by 10%. This amount is increased for each stack of Icy Talons you have and it can stack up to 2 additional times.
    the_long_winter             = { 101932, 456240, 1 }, -- While Pillar of Frost is active your auto-attack critical strikes increase its duration by 2 sec, up to a maximum of 6 sec.
    unleashed_frenzy            = {  76118, 376905, 1 }, -- Damaging an enemy with a Runic Power ability increases your Strength by 2% for 10 sec, stacks up to 3 times.

    -- Rider of the Apocalypse
    a_feast_of_souls            = {  95042, 444072, 1 }, -- While you have 2 or more Horsemen aiding you, your Runic Power spending abilities deal 20% increased damage.
    apocalypse_now              = {  95041, 444040, 1 }, -- Army of the Dead and Frostwyrm's Fury call upon all 4 Horsemen to aid you for 20 sec.
    death_charge                = {  95060, 444010, 1 }, -- Call upon your Death Charger to break free of movement impairment effects. For 10 sec, while upon your Death Charger your movement speed is increased by 100%, you cannot be slowed below 100% of normal speed, and you are immune to forced movement effects and knockbacks.
    fury_of_the_horsemen        = {  95042, 444069, 1 }, -- Every 50 Runic Power you spend extends the duration of the Horsemen's aid in combat by 1 sec, up to 5 sec.
    horsemens_aid               = {  95037, 444074, 1 }, -- While at your aid, the Horsemen will occasionally cast Anti-Magic Shell on you and themselves at 80% effectiveness. You may only benefit from this effect every 45 sec.
    hungering_thirst            = {  95044, 444037, 1 }, -- The damage of your diseases and Frost Strike are increased by 10%.
    mawsworn_menace             = {  95054, 444099, 1 }, -- Obliterate deals 10% increased damage and the cooldown of your Death and Decay is reduced by 10 sec.
    mograines_might             = {  95067, 444047, 1 }, -- Your damage is increased by 5% and you gain the benefits of your Death and Decay while inside Mograine's Death and Decay.
    nazgrims_conquest           = {  95059, 444052, 1 }, -- If an enemy dies while Nazgrim is active, the strength of Apocalyptic Conquest is increased by 3%. Additionally, each Rune you spend increase its value by 1%.
    on_a_paler_horse            = {  95060, 444008, 1 }, -- While outdoors you are able to mount your Acherus Deathcharger in combat.
    pact_of_the_apocalypse      = {  95037, 444083, 1 }, -- When you take damage, 5% of the damage is redirected to each active horsemen.
    riders_champion             = {  95066, 444005, 1, "rider_of_the_apocalypse" }, -- Spending Runes has a chance to call forth the aid of a Horsemen for 10 sec. Mograine Casts Death and Decay at his location that follows his position. Whitemane Casts Undeath on your target dealing 2,608 Shadowfrost damage per stack every 3 sec, for 24 sec. Each time Undeath deals damage it gains a stack. Cannot be Refreshed. Trollbane Casts Chains of Ice on your target slowing their movement speed by 40% and increasing the damage they take from you by 5% for 8 sec. Nazgrim While Nazgrim is active you gain Apocalyptic Conquest, increasing your Strength by 5%.
    trollbanes_icy_fury         = {  95063, 444097, 1 }, -- Obliterate shatters Trollbane's Chains of Ice when hit, dealing 31,015 Shadowfrost damage to nearby enemies, and slowing them by 40% for 4 sec. Deals reduced damage beyond 8 targets.
    whitemanes_famine           = {  95047, 444033, 1 }, -- When Obliterate damages an enemy affected by Undeath it gains 1 stack and infects another nearby enemy.

    -- Deathbringer
    bind_in_darkness            = {  95043, 440031, 1 }, -- Rime empowered Howling Blast deals 30% increased damage to its main target, and is now Shadowfrost. Shadowfrost damage applies 2 stacks to Reaper's Mark and 4 stacks when it is a critical strike.
    dark_talons                 = {  95057, 436687, 1 }, -- Consuming Killing Machine or Rime has a 25% chance to grant 3 stacks of Icy Talons and increase its maximum stacks by the same amount for 6 sec. Runic Power spending abilities count as Shadowfrost while Icy Talons is active.
    deaths_messenger            = {  95049, 437122, 1 }, -- Reduces the cooldowns of Lichborne and Raise Dead by 30 sec.
    expelling_shield            = {  95049, 439948, 1 }, -- When an enemy deals direct damage to your Anti-Magic Shell, their cast speed is reduced by 10% for 6 sec.
    exterminate                 = {  95068, 441378, 1 }, -- After Reaper's Mark explodes, your next 2 Obliterates cost 1 Rune and summon 2 scythes to strike your enemies. The first scythe strikes your target for 74,146 Shadowfrost damage and has a 30% chance to apply Reaper's Mark, the second scythe strikes all enemies around your target for 25,308 Shadowfrost damage. Deals reduced damage beyond 8 targets.
    grim_reaper                 = {  95034, 434905, 1 }, -- Reaper's Mark initial strike grants Killing Machine. Reaper's Mark explosion deals up to 30% increased damage based on your target's missing health.
    pact_of_the_deathbringer    = {  95035, 440476, 1 }, -- When you suffer a damaging effect equal to 25% of your maximum health, you instantly cast Death Pact at 50% effectiveness. May only occur every 2 min. When a Reaper's Mark explodes, the cooldowns of this effect and Death Pact are reduced by 5 sec.
    reaper_of_souls             = {  95034, 440002, 1 }, -- When you apply Reaper's Mark, the cooldown of Soul Reaper is reset, your next Soul Reaper costs no runes, and it explodes on the target regardless of their health. Soul Reaper damage is increased by 20%.
    reapers_mark                = {  95062, 439843, 1, "deathbringer" }, -- Viciously slice into the soul of your enemy, dealing 55,138 Shadowfrost damage and applying Reaper's Mark. Each time you deal Shadow or Frost damage, add a stack of Reaper's Mark. After 12 sec or reaching 40 stacks, the mark explodes, dealing 4,233 damage per stack. Reaper's Mark travels to an unmarked enemy nearby if the target dies, or explodes below 35% health when there are no enemies to travel to. This explosion cannot occur again on a target for 3 min.
    reapers_onslaught           = {  95057, 469870, 1 }, -- Reduces the cooldown of Reaper's Mark by 15 sec, but the amount of Obliterates empowered by Exterminate is reduced by 1.
    rune_carved_plates          = {  95035, 440282, 1 }, -- Each Rune spent reduces the magic damage you take by 1.5% and each Rune generated reduces the physical damage you take by 1.5% for 5 sec, up to 5 times.
    soul_rupture                = {  95061, 437161, 1 }, -- When Reaper's Mark explodes, it deals 30% of the damage dealt to nearby enemies and causes them to deal 5% reduced Physical damage to you for 10 sec.
    swift_and_painful           = {  95032, 443560, 1 }, -- If no enemies are struck by Soul Rupture, you gain 10% Strength for 8 sec. Wave of Souls is 100% more effective on the main target of your Reaper's Mark.
    wave_of_souls               = {  95036, 439851, 1 }, -- Reaper's Mark sends forth bursts of Shadowfrost energy and back, dealing 17,091 Shadowfrost damage both ways to all enemies caught in its path. Wave of Souls critical strikes cause enemies to take 5% increased Shadowfrost damage for 15 sec, stacking up to 2 times, and it is always a critical strike on its way back.
    wither_away                 = {  95058, 441894, 1 }, -- Frost Fever deals its damage 100% faster, and the second scythe of Exterminate applies Frost Fever.
} )


-- PvP Talents
spec:RegisterPvpTalents( {
    bitter_chill      = 5435, -- (356470)
    bloodforged_armor = 5586, -- (410301)
    dark_simulacrum   = 3512, -- (77606) Places a dark ward on an enemy player that persists for 12 sec, triggering when the enemy next spends mana on a spell, and allowing the Death Knight to unleash an exact duplicate of that spell.
    dead_of_winter    = 3743, -- (287250)
    deathchill        =  701, -- (204080)
    delirium          =  702, -- (233396)
    rot_and_wither    = 5510, -- (202727)
    shroud_of_winter  = 3439, -- (199719)
    spellwarden       = 5591, -- (410320)
    strangulate       = 5429, -- (47476) Shadowy tendrils constrict an enemy's throat, silencing them for 4 sec.
} )


-- Auras
spec:RegisterAuras( {
    -- Your Runic Power spending abilities deal $w1% increased damage.
    a_feast_of_souls = {
        id = 440861,
        duration = 3600,
        max_stack = 1,
    },
    -- Talent: Absorbing up to $w1 magic damage.  Immune to harmful magic effects.
    -- https://wowhead.com/beta/spell=48707
    antimagic_shell = {
        id = 48707,
        duration = function () return ( legendary.deaths_embrace.enabled and 2 or 1 ) * 5 + ( conduit.reinforced_shell.mod * 0.001 ) end,
        max_stack = 1
    },
    antimagic_zone = { -- TODO: Modify expiration based on last cast.
        id = 145629,
        duration = 8,
        max_stack = 1
    },
    asphyxiate = {
        id = 108194,
        duration = 4,
        mechanic = "stun",
        type = "Magic",
        max_stack = 1
    },
    -- Next Howling Blast deals Shadowfrost damage.
    bind_in_darkness = {
        id = 443532,
        duration = 3600,
        max_stack = 1,
    },
    -- Talent: Disoriented.
    -- https://wowhead.com/beta/spell=207167
    blinding_sleet = {
        id = 207167,
        duration = 5,
        mechanic = "disorient",
        type = "Magic",
        max_stack = 1
    },
    blood_draw = {
        id = 454871,
        duration = 8,
        max_stack = 1
    },
    -- You may not benefit from the effects of Blood Draw.
    -- https://wowhead.com/beta/spell=374609
    blood_draw_cd = {
        id = 374609,
        duration = 120,
        max_stack = 1
    },
    -- Draining $w1 health from the target every $t1 sec.
    -- https://wowhead.com/beta/spell=55078
    blood_plague = {
        id = 55078,
        duration = function() return 24 * ( talent.wither_away.enabled and 0.5 or 1 ) end,
        tick_time = function() return 3 * ( talent.wither_away.enabled and 0.5 or 1 ) end,
        max_stack = 1
    },
    -- Draining $s1 health from the target every $t1 sec.
    -- https://wowhead.com/beta/spell=206931
    blooddrinker = {
        id = 206931,
        duration = 3,
        type = "Magic",
        max_stack = 1
    },
    bonegrinder_crit = {
        id = 377101,
        duration = 10,
        max_stack = 5
    },
    -- Talent: Frost damage increased by $s1%.
    -- https://wowhead.com/beta/spell=377103
    bonegrinder_frost = {
        id = 377103,
        duration = 10,
        max_stack = 1
    },
    -- Talent: Continuously dealing Frost damage every $t1 sec to enemies in a cone in front of you.
    -- https://wowhead.com/beta/spell=152279
    breath_of_sindragosa = {
        id = 152279,
        duration = 10,
        tick_time = 1,
        max_stack = 1,
        meta = {
            remains = function( t )
                if not t.up then return 0 end
                return ( runic_power.current + ( runes.current * 10 ) ) / 16
            end,
        }
    },
    -- Talent: Movement slowed $w1% $?$w5!=0[and Haste reduced $w5% ][]by frozen chains.
    -- https://wowhead.com/beta/spell=45524
    chains_of_ice = {
        id = 45524,
        duration = 8,
        mechanic = "snare",
        type = "Magic",
        max_stack = 1
    },
    chilled = {
        id = 204206,
        duration = 4,
        mechanic = "snare",
        type = "Magic",
        max_stack = 1
    },
    cold_heart_item = {
        id = 235599,
        duration = 3600,
        max_stack = 20
    },
    -- Talent: Your next Chains of Ice will deal $281210s1 Frost damage.
    -- https://wowhead.com/beta/spell=281209
    cold_heart_talent = {
        id = 281209,
        duration = 3600,
        max_stack = 20,
    },
    cold_heart = {
        alias = { "cold_heart_item", "cold_heart_talent" },
        aliasMode = "first",
        aliasType = "buff",
        duration = 3600,
        max_stack = 20,
    },
    -- Talent: Controlled.
    -- https://wowhead.com/beta/spell=111673
    control_undead = {
        id = 111673,
        duration = 300,
        mechanic = "charm",
        type = "Magic",
        max_stack = 1
    },
    cryogenic_chamber = {
        id = 456370,
        duration = 30,
        max_stack = 20
    },
    -- Taunted.
    -- https://wowhead.com/beta/spell=56222
    dark_command = {
        id = 56222,
        duration = 3,
        mechanic = "taunt",
        max_stack = 1
    },
    dark_succor = {
        id = 101568,
        duration = 20,
        max_stack = 1
    },
    -- Reduces healing done by $m1%.
    -- https://wowhead.com/beta/spell=327095
    death = {
        id = 327095,
        duration = 6,
        type = "Magic",
        max_stack = 3
    },
    death_and_decay = { -- Buff.
        id = 188290,
        duration = 10,
        tick_time = 1,
        max_stack = 1
    },
    -- [444347] $@spelldesc444010
    death_charge = {
        id = 444347,
        duration = 10,
        max_stack = 1,
    },
    -- Talent: The next $w2 healing received will be absorbed.
    -- https://wowhead.com/beta/spell=48743
    death_pact = {
        id = 48743,
        duration = 15,
        max_stack = 1
    },
    -- Your movement speed is increased by $s1%, you cannot be slowed below $s2% of normal speed, and you are immune to forced movement effects and knockbacks.
    -- https://wowhead.com/beta/spell=48265
    deaths_advance = {
        id = 48265,
        duration = 10,
        type = "Magic",
        max_stack = 1
    },
    -- Talent: Haste increased by $s3%.  Generating $s1 $LRune:Runes; and ${$m2/10} Runic Power every $t1 sec.
    -- https://wowhead.com/beta/spell=47568
    empower_rune_weapon = {
        id = 47568,
        duration = 20,
        tick_time = 5,
        max_stack = 1
    },
    -- Talent: When Pillar of Frost expires, you will gain $s1% Strength for $<duration> sec.
    -- https://wowhead.com/beta/spell=377192
    enduring_strength = {
        id = 377192,
        duration = 20,
        max_stack = 20
    },
    -- Talent: Strength increased by $w1%.
    -- https://wowhead.com/beta/spell=377195
    enduring_strength_buff = {
        id = 377195,
        duration = 6,
        max_stack = 1
    },
    everfrost = {
        id = 376974,
        duration = 8,
        max_stack = 10
    },
    -- Casting speed reduced by $w1%.
    expelling_shield = {
        id = 440739,
        duration = 6.0,
        max_stack = 1,
    },
    -- Reduces damage dealt to $@auracaster by $m1%.
    -- https://wowhead.com/beta/spell=327092
    famine = {
        id = 327092,
        duration = 6,
        max_stack = 3
    },
    -- Suffering $w1 Frost damage every $t1 sec.
    -- https://wowhead.com/beta/spell=55095
    frost_fever = {
        id = 55095,
        duration = function() return 24 * ( talent.wither_away.enabled and 0.5 or 1 ) end,
        tick_time = function() return 3 * ( talent.wither_away.enabled and 0.5 or 1 ) end,
        max_stack = 1
    },
    -- Talent: Grants ${$s1*$mas}% Mastery.
    -- https://wowhead.com/beta/spell=377253
    frostwhelps_aid = {
        id = 377253,
        duration = 15,
        type = "Magic",
        max_stack = 5
    },
    -- Talent: Movement speed slowed by $s2%.
    -- https://wowhead.com/beta/spell=279303
    frostwyrms_fury = {
        id = 279303,
        duration = 10,
        type = "Magic",
        max_stack = 1
    },
    frozen_pulse = {
        -- Pseudo aura for legacy talent.
        name = "Frozen Pulse",
        meta = {
            up = function () return runes.current < 3 end,
            down = function () return runes.current >= 3 end,
            stack = function () return runes.current < 3 and 1 or 0 end,
            duration = 15,
            remains = function () return runes.time_to_3 end,
            applied = function () return runes.current < 3 and query_time or 0 end,
            expires = function () return runes.current < 3 and ( runes.time_to_3 + query_time ) or 0 end,
        }
    },
    -- Dealing $w1 Frost damage every $t1 sec.
    -- https://wowhead.com/beta/spell=274074
    glacial_contagion = {
        id = 274074,
        duration = 14,
        tick_time = 2,
        type = "Magic",
        max_stack = 1
    },
    -- Dealing $w1 Shadow damage every $t1 sec.
    -- https://wowhead.com/beta/spell=275931
    harrowing_decay = {
        id = 275931,
        duration = 4,
        tick_time = 1,
        type = "Magic",
        max_stack = 1
    },
    -- Deals $s1 Fire damage.
    -- https://wowhead.com/beta/spell=286979
    helchains = {
        id = 286979,
        duration = 15,
        tick_time = 1,
        type = "Magic",
        max_stack = 1
    },
    -- Rooted.
    ice_prison = {
        id = 454787,
        duration = 4.0,
        max_stack = 1,
    },
    -- Talent: Damage taken reduced by $w3%.  Immune to Stun effects.
    -- https://wowhead.com/beta/spell=48792
    icebound_fortitude = {
        id = 48792,
        duration = 8,
        tick_time = 1.0,
        max_stack = 1
    },
    icy_talons = {
        id = 194879,
        duration = 6,
        max_stack = function() return ( talent.smothering_offense.enabled and 5 or 3 ) + ( talent.dark_talons.enabled and 2 or 0 ) end,
    },
    inexorable_assault = {
        id = 253595,
        duration = 3600,
        max_stack = 5,
    },
    insidious_chill = {
        id = 391568,
        duration = 30,
        max_stack = 4
    },
    -- Talent: Guaranteed critical strike on your next Obliterate$?s207230[ or Frostscythe][].
    -- https://wowhead.com/beta/spell=51124
    killing_machine = {
        id = 51124,
        duration = 10,
        max_stack = function() return 1 + talent.fatal_fixation.rank end,
    },
    -- Absorbing up to $w1 magic damage.; Duration of harmful magic effects reduced by $s2%.
    lesser_antimagic_shell = {
        id = 454863,
        duration = function() return 5.0 * ( talent.antimagic_barrier.enabled and 1.4 or 1 ) end,
        max_stack = 1,

        -- Affected by:
        -- fatal_fixation[405166] #0: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER, 'points': 1.0, 'target': TARGET_UNIT_CASTER, 'modifies': MAX_STACKS, }
        -- antimagic_barrier[205727] #0: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER, 'points': -20000.0, 'target': TARGET_UNIT_CASTER, 'modifies': COOLDOWN, }
        -- antimagic_barrier[205727] #1: { 'type': APPLY_AURA, 'subtype': ADD_PCT_MODIFIER, 'pvp_multiplier': 0.5, 'points': 40.0, 'target': TARGET_UNIT_CASTER, 'modifies': BUFF_DURATION, }
        -- osmosis[454835] #0: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER, 'points': 15.0, 'target': TARGET_UNIT_CASTER, 'modifies': EFFECT_4_VALUE, }
        -- unyielding_will[457574] #1: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER, 'points': 20000.0, 'target': TARGET_UNIT_CASTER, 'modifies': COOLDOWN, }
        -- spellwarden[410320] #0: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER, 'points': -10000.0, 'target': TARGET_UNIT_CASTER, 'modifies': COOLDOWN, }
    },
    -- Casting speed reduced by $w1%.
    -- https://wowhead.com/beta/spell=326868
    lethargy = {
        id = 326868,
        duration = 6,
        max_stack = 1
    },
    -- Leech increased by $s1%$?a389682[, damage taken reduced by $s8%][] and immune to Charm, Fear and Sleep. Undead.
    -- https://wowhead.com/beta/spell=49039
    lichborne = {
        id = 49039,
        duration = 10,
        tick_time = 1,
        max_stack = 1
    },
    march_of_darkness = {
        id = 391547,
        duration = 3,
        max_stack = 1
    },
    -- Talent: $@spellaura281238
    -- https://wowhead.com/beta/spell=207256
    obliteration = {
        id = 207256,
        duration = 3600,
        max_stack = 1
    },
    -- Grants the ability to walk across water.
    -- https://wowhead.com/beta/spell=3714
    path_of_frost = {
        id = 3714,
        duration = 600,
        tick_time = 0.5,
        max_stack = 1
    },
    -- Suffering $o1 shadow damage over $d and slowed by $m2%.
    -- https://wowhead.com/beta/spell=327093
    pestilence = {
        id = 327093,
        duration = 6,
        tick_time = 1,
        type = "Magic",
        max_stack = 3
    },
    -- Talent: Strength increased by $w1%.
    -- https://wowhead.com/beta/spell=51271
    pillar_of_frost = {
        id = 51271,
        duration = 12,
        type = "Magic",
        max_stack = 1
    },
    -- Frost damage taken from the Death Knight's abilities increased by $s1%.
    -- https://wowhead.com/beta/spell=51714
    razorice = {
        id = 51714,
        duration = 20,
        tick_time = 1,
        type = "Magic",
        max_stack = 5
    },
    -- You are a prey for the Deathbringer... This effect will explode for $436304s1 Shadowfrost damage for each stack.
    reapers_mark = {
        id = 434765,
        duration = 12.0,
        tick_time = 1.0,
        max_stack = 40,
    },
    -- Talent: Dealing $196771s1 Frost damage to enemies within $196771A1 yards each second.
    -- https://wowhead.com/beta/spell=196770
    remorseless_winter = {
        id = 196770,
        duration = 8,
        tick_time = 1,
        max_stack = 1
    },
    -- Talent: Movement speed reduced by $s1%.
    -- https://wowhead.com/beta/spell=211793
    remorseless_winter_snare = {
        id = 211793,
        duration = 3,
        type = "Magic",
        max_stack = 1
    },
    -- Talent: Your next Howling Blast will consume no Runes, generate no Runic Power, and deals $s2% additional damage.
    -- https://wowhead.com/beta/spell=59052
    rime = {
        id = 59052,
        duration = 15,
        type = "Magic",
        max_stack = 1
    },
    -- Magical damage taken reduced by $w1%.
    rune_carved_plates = {
        id = 440290,
        duration = 5.0,
        max_stack = 1,
    },
    -- Talent: Strength increased by $w1%
    -- https://wowhead.com/beta/spell=374585
    rune_mastery = {
        id = 374585,
        duration = 8,
        max_stack = 1
    },
    -- Runic Power generation increased by $s1%.
    -- https://wowhead.com/beta/spell=326918
    rune_of_hysteria = {
        id = 326918,
        duration = 8,
        max_stack = 1
    },
    -- Healing for $s1% of your maximum health every $t sec.
    -- https://wowhead.com/beta/spell=326808
    rune_of_sanguination = {
        id = 326808,
        duration = 8,
        max_stack = 1
    },
    -- Absorbs $w1 magic damage.    When an enemy damages the shield, their cast speed is reduced by $w2% for $326868d.
    -- https://wowhead.com/beta/spell=326867
    rune_of_spellwarding = {
        id = 326867,
        duration = 8,
        max_stack = 1
    },
    -- Haste and Movement Speed increased by $s1%.
    -- https://wowhead.com/beta/spell=326984
    rune_of_unending_thirst = {
        id = 326984,
        duration = 10,
        max_stack = 1
    },
    -- Talent: Afflicted by Soul Reaper, if the target is below $s3% health this effect will explode dealing an additional $343295s1 Shadowfrost damage.
    -- https://wowhead.com/beta/spell=448229
    soul_reaper = {
        id = 448229,
        duration = 5,
        tick_time = 5,
        max_stack = 1
    },
    -- Silenced.
    strangulate = {
        id = 47476,
        duration = 5.0,
        max_stack = 1,
    },
    -- Damage dealt to $@auracaster reduced by $w1%.
    subduing_grasp = {
        id = 454824,
        duration = 6.0,
        max_stack = 1,
    },
    -- Damage taken from area of effect attacks reduced by an additional $w1%.
    suppression = {
        id = 454886,
        duration = 6.0,
        max_stack = 1,
    },
    -- Deals $s1 Fire damage.
    -- https://wowhead.com/beta/spell=319245
    unholy_pact = {
        id = 319245,
        duration = 15,
        tick_time = 1,
        type = "Magic",
        max_stack = 1
    },
    -- Talent: Strength increased by 0%
    unleashed_frenzy = {
        id = 376907,
        duration = 10, -- 20230206 Hotfix
        max_stack = 3
    },
    -- The touch of the spirit realm lingers....
    -- https://wowhead.com/beta/spell=97821
    voidtouched = {
        id = 97821,
        duration = 300,
        max_stack = 1
    },
    -- Increases damage taken from $@auracaster by $m1%.
    -- https://wowhead.com/beta/spell=327096
    war = {
        id = 327096,
        duration = 6,
        type = "Magic",
        max_stack = 3
    },
    -- Talent: Movement speed increased by $w1%.  Cannot be slowed below $s2% of normal movement speed.  Cannot attack.
    -- https://wowhead.com/beta/spell=212552
    wraith_walk = {
        id = 212552,
        duration = 4,
        max_stack = 1
    },

    -- PvP Talents
    -- Your next spell with a mana cost will be copied by the Death Knight's runeblade.
    dark_simulacrum = {
        id = 77606,
        duration = 12,
        max_stack = 1,
    },
    -- Your runeblade contains trapped magical energies, ready to be unleashed.
    dark_simulacrum_buff = {
        id = 77616,
        duration = 12,
        max_stack = 1,
    },
    dead_of_winter = {
        id = 289959,
        duration = 4,
        max_stack = 5,
    },
    deathchill = {
        id = 204085,
        duration = 4,
        max_stack = 1
    },
    delirium = {
        id = 233396,
        duration = 15,
        max_stack = 1,
    },
    shroud_of_winter = {
        id = 199719,
        duration = 3600,
        max_stack = 1,
    },

    -- Legendary
    absolute_zero = {
        id = 334693,
        duration = 3,
        max_stack = 1,
    },

    -- Azerite Powers
    cold_hearted = {
        id = 288426,
        duration = 8,
        max_stack = 1
    },
    frostwhelps_indignation = {
        id = 287338,
        duration = 6,
        max_stack = 1,
    },
} )


spec:RegisterTotem( "ghoul", 1100170 )


-- Tier 29
spec:RegisterGear( "tier29", 200405, 200407, 200408, 200409, 200410 )

-- Tier 30
spec:RegisterGear( "tier30", 202464, 202462, 202461, 202460, 202459, 217223, 217225, 217221, 217222, 217224 )
-- 2 pieces (Frost) : Howling Blast damage increased by 20%. Consuming Rime increases the damage of your next Frostwyrm's Fury by 5%, stacking 10 times. Pillar of Frost calls a Frostwyrm's Fury at 40% effectiveness that cannot Freeze enemies.
spec:RegisterAura( "wrath_of_the_frostwyrm", {
    id = 408368,
    duration = 30,
    max_stack = 10
} )
-- 4 pieces (Frost) : Frostwyrm's Fury causes enemies hit to take 25% increased damage from your critical strikes for 12 sec.
spec:RegisterAura( "lingering_chill", {
    id = 410879,
    duration = 12,
    max_stack = 1
} )

spec:RegisterGear( "tier31", 207198, 207199, 207200, 207201, 207203 )
-- (2) Chill Streak's range is increased by $s1 yds and can bounce off of you. Each time Chill Streak bounces your damage is increased by $424165s2% for $424165d, stacking up to $424165u times.
-- (4) Chill Streak can bounce $s1 additional times and each time it bounces, you have a $s4% chance to gain a Rune, reduce Chill Streak cooldown by ${$s2/1000} sec, or reduce the cooldown of Empower Rune Weapon by ${$s3/1000} sec.
spec:RegisterAura( "chilling_rage", {
    id = 424165,
    duration = 12,
    max_stack = 5
} )



local TriggerERW = setfenv( function()
    gain( 1, "runes" )
    gain( 5, "runic_power" )
end, state )

local any_dnd_set = false

spec:RegisterHook( "reset_precast", function ()
    if state:IsKnown( "deaths_due" ) then
        class.abilities.any_dnd = class.abilities.deaths_due
        cooldown.any_dnd = cooldown.deaths_due
        setCooldown( "death_and_decay", cooldown.deaths_due.remains )
    elseif state:IsKnown( "defile" ) then
        class.abilities.any_dnd = class.abilities.defile
        cooldown.any_dnd = cooldown.defile
        setCooldown( "death_and_decay", cooldown.defile.remains )
    else
        class.abilities.any_dnd = class.abilities.death_and_decay
        cooldown.any_dnd = cooldown.death_and_decay
    end

    if not any_dnd_set then
        class.abilityList.any_dnd = "|T136144:0|t |cff00ccff[Any]|r " .. class.abilities.death_and_decay.name
        any_dnd_set = true
    end

    local control_expires = action.control_undead.lastCast + 300
    if control_expires > now and pet.up then
        summonPet( "controlled_undead", control_expires - now )
    end

    -- Reset CDs on any Rune abilities that do not have an actual cooldown.
    for action in pairs( class.abilityList ) do
        local data = class.abilities[ action ]
        if data and data.cooldown == 0 and data.spendType == "runes" then
            setCooldown( action, 0 )
        end
    end

    if buff.empower_rune_weapon.up then
        local expires = buff.empower_rune_weapon.expires

        while expires >= query_time do
            state:QueueAuraExpiration( "empower_rune_weapon", TriggerERW, expires )
            expires = expires - 5
        end
    end
end )


spec:RegisterHook( "recheck", function( times )
    if buff.breath_of_sindragosa.up then
        local applied = action.breath_of_sindragosa.lastCast
        local tick = applied + ceil( query_time - applied ) - query_time
        if tick > 0 then times[ #times + 1 ] = tick end
        times[ #times + 1 ] = tick + 1
        times[ #times + 1 ] = tick + 2
        times[ #times + 1 ] = tick + 3
        if Hekili.ActiveDebug then Hekili:Debug( "Queued BoS recheck times at %.2f, %.2f, %.2f, and %.2f.", tick, tick + 1, tick + 2, tick + 3 ) end
    end
end )


-- Abilities
spec:RegisterAbilities( {
    -- Talent: Surrounds you in an Anti-Magic Shell for $d, absorbing up to $<shield> magic damage and preventing application of harmful magical effects.$?s207188[][ Damage absorbed generates Runic Power.]
    antimagic_shell = {
        id = 48707,
        cast = 0,
        cooldown = function() return 60 - ( talent.antimagic_barrier.enabled and 15 or 0 ) - ( talent.unyielding_will.enabled and -20 or 0 ) - ( pvptalent.spellwarden.enabled and 10 or 0 ) end,
        gcd = "off",

        startsCombat = false,

        toggle = function()
            if settings.ams_usage == "defensives" or settings.ams_usage == "both" then return "defensives" end
        end,

        usable = function()
            if settings.ams_usage == "damage" or settings.ams_usage == "both" then return incoming_magic_3s > 0, "settings require magic damage taken in the past 3 seconds" end
        end,

        handler = function ()
            applyBuff( "antimagic_shell" )
            if talent.unyielding_will.enabled then removeBuff( "dispellable_magic" ) end
        end,
    },

    -- Talent: Places an Anti-Magic Zone that reduces spell damage taken by party or raid members by $145629m1%. The Anti-Magic Zone lasts for $d or until it absorbs $?a374383[${$<absorb>*1.1}][$<absorb>] damage.
    antimagic_zone = {
        id = 51052,
        cast = 0,
        cooldown = function() return 120 - ( talent.assimilation.enabled and 30 or 0 ) end,
        gcd = "spell",

        talent = "antimagic_zone",
        startsCombat = false,

        toggle = "defensives",

        handler = function ()
            applyBuff( "antimagic_zone" )
        end,
    },

    -- Talent: Lifts the enemy target off the ground, crushing their throat with dark energy and stunning them for $d.
    asphyxiate = {
        id = 221562,
        cast = 0,
        cooldown = 45,
        gcd = "spell",

        talent = "asphyxiate",
        startsCombat = false,

        toggle = "interrupts",

        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            applyDebuff( "target", "asphyxiate" )
            interrupt()
        end,
    },

    -- Talent: Targets in a cone in front of you are blinded, causing them to wander disoriented for $d. Damage may cancel the effect.    When Blinding Sleet ends, enemies are slowed by $317898s1% for $317898d.
    blinding_sleet = {
        id = 207167,
        cast = 0,
        cooldown = 60,
        gcd = "spell",

        talent = "blinding_sleet",
        startsCombat = false,

        toggle = "cooldowns",

        handler = function ()
            applyDebuff( "target", "blinding_sleet" )
            active_dot.blinding_sleet = max( active_dot.blinding_sleet, active_enemies )
        end,
    },

    -- Talent: Continuously deal ${$155166s2*$<CAP>/$AP} Frost damage every $t1 sec to enemies in a cone in front of you, until your Runic Power is exhausted. Deals reduced damage to secondary targets.    |cFFFFFFFFGenerates $303753s1 $lRune:Runes; at the start and end.|r
    breath_of_sindragosa = {
        id = 152279,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        spend = 18,
        spendType = "runic_power",
        readySpend = function () return settings.bos_rp end,

        talent = "breath_of_sindragosa",
        startsCombat = true,

        toggle = "cooldowns",

        handler = function ()
            gain( 2, "runes" )
            applyBuff( "breath_of_sindragosa" )
            if talent.unleashed_frenzy.enabled then addStack( "unleashed_frenzy", nil, 3 ) end
        end,
    },

    -- Talent: Shackles the target $?a373930[and $373930s1 nearby enemy ][]with frozen chains, reducing movement speed by $s1% for $d.
    chains_of_ice = {
        id = 45524,
        cast = 0,
        cooldown = function() return 0 + ( talent.ice_prison.enabled and 12 or 0 ) end,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "chains_of_ice" )
            if talent.ice_prison.enabled then applyDebuff( "target", "ice_prison" ) end
            removeBuff( "cold_heart_item" )
            removeBuff( "cold_heart_talent" )
        end,
    },

    -- Talent: Deals $204167s4 Frost damage to the target and reduces their movement speed by $204206m2% for $204206d.    Chill Streak bounces up to $m1 times between closest targets within $204165A1 yards.
    chill_streak = {
        id = 305392,
        cast = 0,
        cooldown = 45,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        talent = "chill_streak",
        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "chilled" )
            if set_bonus.tier31_2pc > 0 then
                applyBuff( "chilling_rage", 5 ) -- TODO: Check if reliable.
            end
        end,
    },

    -- Talent: Dominates the target undead creature up to level $s1, forcing it to do your bidding for $d.
    control_undead = {
        id = 111673,
        cast = 1.5,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        talent = "control_undead",
        startsCombat = false,

        usable = function () return target.is_undead and target.level <= level + 1, "requires undead target up to 1 level above player" end,
        handler = function ()
            summonPet( "controlled_undead", 300 )
        end,
    },

    -- Command the target to attack you.
    dark_command = {
        id = 56222,
        cast = 0,
        cooldown = 8,
        gcd = "off",

        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "dark_command" )
        end,
    },


    dark_simulacrum = {
        id = 77606,
        cast = 0,
        cooldown = 20,
        gcd = "spell",

        startsCombat = true,
        texture = 135888,

        pvptalent = "dark_simulacrum",

        usable = function ()
            if not target.is_player then return false, "target is not a player" end
            return true
        end,
        handler = function ()
            applyDebuff( "target", "dark_simulacrum" )
        end,
    },

    -- Corrupts the targeted ground, causing ${$341340m1*11} Shadow damage over $d to targets within the area.$?!c2[; While you remain within the area, your ][]$?s223829&!c2[Necrotic Strike and ][]$?c1[Heart Strike will hit up to $188290m3 additional targets.]?s207311&!c2[Clawing Shadows will hit up to ${$55090s4-1} enemies near the target.]?!c2[Scourge Strike will hit up to ${$55090s4-1} enemies near the target.][; While you remain within the area, your Obliterate will hit up to $316916M2 additional $Ltarget:targets;.]
    death_and_decay = {
        id = 43265,
        noOverride = 324128,
        cast = 0,
        charges = function() if talent.deaths_echo.enabled then return 2 end end,
        cooldown = 30,
        recharge = function() if talent.deaths_echo.enabled then return 30 end end,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,

        handler = function ()
            applyBuff( "death_and_decay" )
            applyDebuff( "target", "death_and_decay" )
        end,
    },

    -- Fires a blast of unholy energy at the target$?a377580[ and $377580s2 additional nearby target][], causing $47632s1 Shadow damage to an enemy or healing an Undead ally for $47633s1 health.$?s390268[    Increases the duration of Dark Transformation by $390268s1 sec.][]
    death_coil = {
        id = 47541,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 30,
        spendType = "runic_power",

        startsCombat = true,

        handler = function ()
            if buff.dark_transformation.up then buff.dark_transformation.up.expires = buff.dark_transformation.expires + 1 end
            if talent.unleashed_frenzy.enabled then addStack( "unleashed_frenzy", nil, 3 ) end
        end,
    },

    -- Opens a gate which you can use to return to Ebon Hold.    Using a Death Gate while in Ebon Hold will return you back to near your departure point.
    death_gate = {
        id = 50977,
        cast = 4,
        cooldown = 60,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = false,

        handler = function ()
        end,
    },

    -- Harnesses the energy that surrounds and binds all matter, drawing the target toward you$?a389679[ and slowing their movement speed by $389681s1% for $389681d][]$?s137008[ and forcing the enemy to attack you][].
    death_grip = {
        id = 49576,
        cast = 0,
        charges = function() if talent.deaths_echo.enabled then return 2 end end,
        cooldown = 25,
        recharge = function() if talent.deaths_echo.enabled then return 25 end end,

        gcd = "off",

        startsCombat = false,

        handler = function ()
            applyDebuff( "target", "death_grip" )
            setDistance( 5 )
            if conduit.unending_grip.enabled then applyDebuff( "target", "unending_grip" ) end
        end,
    },

    -- Talent: Create a death pact that heals you for $s1% of your maximum health, but absorbs incoming healing equal to $s3% of your max health for $d.
    death_pact = {
        id = 48743,
        cast = 0,
        cooldown = 120,
        gcd = "off",

        talent = "death_pact",
        startsCombat = false,

        toggle = "defensives",

        handler = function ()
            gain( health.max * 0.5, "health" )
            applyDebuff( "player", "death_pact" )
        end,
    },

    -- Talent: Focuses dark power into a strike$?s137006[ with both weapons, that deals a total of ${$s1+$66188s1}][ that deals $s1] Physical damage and heals you for ${$s2}.2% of all damage taken in the last $s4 sec, minimum ${$s3}.1% of maximum health.
    death_strike = {
        id = 49998,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = function ()
            if buff.dark_succor.up then return 0 end
            return ( talent.improved_death_strike.enabled and 40 or 50 ) - ( buff.blood_draw.up and 10 or 0 )
        end,
        spendType = "runic_power",

        talent = "death_strike",
        startsCombat = true,

        handler = function ()
            removeBuff( "dark_succor" )
            gain( health.max * 0.10, "health" )
            if talent.unleashed_frenzy.enabled then addStack( "unleashed_frenzy", nil, 3 ) end
        end,
    },

    -- For $d, your movement speed is increased by $s1%, you cannot be slowed below $s2% of normal speed, and you are immune to forced movement effects and knockbacks.    |cFFFFFFFFPassive:|r You cannot be slowed below $124285s1% of normal speed.
    deaths_advance = {
        id = 48265,
        cast = 0,
        charges = function() if talent.deaths_echo.enabled then return 2 end end,
        cooldown = 45,
        recharge = function() if talent.deaths_echo.enabled then return 45 end end,

        gcd = "off",

        startsCombat = false,

        handler = function ()
            applyBuff( "deaths_advance" )
            if conduit.fleeting_wind.enabled then applyBuff( "fleeting_wind" ) end
        end,
    },

    -- Talent: Empower your rune weapon, gaining $s3% Haste and generating $s1 $LRune:Runes; and ${$m2/10} Runic Power instantly and every $t1 sec for $d.  $?s137006[  If you already know $@spellname47568, instead gain $392714s1 additional $Lcharge:charges; of $@spellname47568.][]
    empower_rune_weapon = {
        id = 47568,
        cast = 0,
        charges = function()
            if talent.empower_rune_weapon.rank + talent.empower_rune_weapon_2.rank > 1 then return 2 end
        end,
        cooldown = function () return ( conduit.accelerated_cold.enabled and 0.9 or 1 ) * ( essence.vision_of_perfection.enabled and 0.87 or 1 ) * ( level > 55 and 105 or 120 ) end,
        recharge = function ()
            if talent.empower_rune_weapon.rank + talent.empower_rune_weapon_2.rank > 1 then return ( conduit.accelerated_cold.enabled and 0.9 or 1 ) * ( essence.vision_of_perfection.enabled and 0.87 or 1 ) * ( level > 55 and 105 or 120 ) end
        end,
        gcd = "off",

        talent = "empower_rune_weapon",
        startsCombat = false,

        usable = function() return talent.empower_rune_weapon.rank + talent.empower_rune_weapon_2.rank > 0, "requires an empower_rune_weapon talent" end,

        handler = function ()
            stat.haste = state.haste + 0.15 + ( conduit.accelerated_cold.mod * 0.01 )
            gain( 1, "runes" )
            gain( 5, "runic_power" )
            applyBuff( "empower_rune_weapon" )
            state:QueueAuraExpiration( "empower_rune_weapon", TriggerERW, query_time + 5 )
            state:QueueAuraExpiration( "empower_rune_weapon", TriggerERW, query_time + 10 )
            state:QueueAuraExpiration( "empower_rune_weapon", TriggerERW, query_time + 15 )
            state:QueueAuraExpiration( "empower_rune_weapon", TriggerERW, query_time + 20 )
        end,

        copy = "empowered_rune_weapon"
    },

    -- Talent: Chill your $?$owb==0[weapon with icy power and quickly strike the enemy, dealing $<2hDamage> Frost damage.][weapons with icy power and quickly strike the enemy with both, dealing a total of $<dualWieldDamage> Frost damage.]
    frost_strike = {
        id = 49143,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 30,
        spendType = "runic_power",

        talent = "frost_strike",
        startsCombat = true,

        cycle = function ()
            if debuff.mark_of_fyralath.up then return "mark_of_fyralath" end
            if death_knight.runeforge.razorice and debuff.razorice.stack == 5 then return "razorice" end
        end,

        handler = function ()
            applyDebuff( "target", "razorice", 20, 2 )

            if talent.obliteration.enabled and buff.pillar_of_frost.up then addStack( "killing_machine" ) end
            removeBuff( "eradicating_blow" )

            if talent.shattering_blade.enabled then
                if debuff.razorice.stack == 5 then removeDebuff( "target", "razorice" )
                elseif debuff.razorice.stack > 5 then applyDebuff( "target", "razorice", nil, debuff.razorice.stack - 5 ) end
            end

            if talent.unleashed_frenzy.enabled then addStack( "unleashed_frenzy", nil, 3 ) end

            if pvptalent.bitter_chill.enabled and debuff.chains_of_ice.up then
                applyDebuff( "target", "chains_of_ice" )
            end
        end,

        auras = {
            unleashed_frenzy = {
                id = 338501,
                duration = 6,
                max_stack = 5,
            }
        }
    },

    -- A sweeping attack that strikes all enemies in front of you for $s2 Frost damage. This attack always critically strikes and critical strikes with Frostscythe deal $s3 times normal damage. Deals reduced damage beyond $s5 targets. ; Consuming Killing Machine reduces the cooldown of Frostscythe by ${$s1/1000}.1 sec.
    frostscythe = {
        id = 207230,
        cast = 0,
        cooldown = 30,
        gcd = "spell",

        spend = 2,
        spendType = "runes",

        talent = "frostscythe",
        startsCombat = true,

        range = 7,

        handler = function ()
            removeStack( "inexorable_assault" )

            if buff.killing_machine.up and talent.bonegrinder.enabled then
                if buff.bonegrinder_crit.stack_pct == 100 then
                    removeBuff( "bonegrinder_crit" )
                    applyBuff( "bonegrinder_frost" )
                else
                    addStack( "bonegrinder_crit" )
                end
                removeBuff( "killing_machine" )
            end
        end,
    },

    -- Talent: Summons a frostwyrm who breathes on all enemies within $s1 yd in front of you, dealing $279303s1 Frost damage and slowing movement speed by $279303s2% for $279303d.
    frostwyrms_fury = {
        id = 279302,
        cast = 0,
        cooldown = function () return legendary.absolute_zero.enabled and 90 or 180 end,
        gcd = "spell",

        talent = "frostwyrms_fury",
        startsCombat = true,

        toggle = "cooldowns",

        handler = function ()
            applyDebuff( "target", "frostwyrms_fury" )
            if set_bonus.tier30_4pc > 0 then applyDebuff( "target", "lingering_chill" ) end
            if legendary.absolute_zero.enabled then applyDebuff( "target", "absolute_zero" ) end
        end,
    },

    -- Talent: Summon glacial spikes from the ground that advance forward, each dealing ${$195975s1*$<CAP>/$AP} Frost damage and applying Razorice to enemies near their eruption point.
    glacial_advance = {
        id = 194913,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 30,
        spendType = "runic_power",

        talent = "glacial_advance",
        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "razorice", nil, min( 5, buff.razorice.stack + 1 ) )
            if active_enemies > 1 then active_dot.razorice = active_enemies end
            if talent.obliteration.enabled and buff.pillar_of_frost.up then addStack( "killing_machine" ) end
            if talent.unleashed_frenzy.enabled then addStack( "unleashed_frenzy", nil, 3 ) end
        end,
    },

    -- Talent: Blow the Horn of Winter, gaining $s1 $LRune:Runes; and generating ${$s2/10} Runic Power.
    horn_of_winter = {
        id = 57330,
        cast = 0,
        cooldown = 45,
        gcd = "spell",

        talent = "horn_of_winter",
        startsCombat = false,

        handler = function ()
            gain( 2, "runes" )
            gain( 25, "runic_power" )
        end,
    },

    -- Talent: Blast the target with a frigid wind, dealing ${$s1*$<CAP>/$AP} $?s204088[Frost damage and applying Frost Fever to the target.][Frost damage to that foe, and reduced damage to all other enemies within $237680A1 yards, infecting all targets with Frost Fever.]    |Tinterface\icons\spell_deathknight_frostfever.blp:24|t |cFFFFFFFFFrost Fever|r  $@spelldesc55095
    howling_blast = {
        id = 49184,
        cast = 0,
        cooldown = 0,
        gcd = "spell",
        school = function() return talent.bind_in_darkness.enabled and "shadowfrost" or "frost" end,

        spend = function () return buff.rime.up and 0 or 1 end,
        spendType = "runes",

        talent = "howling_blast",
        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "frost_fever" )
            active_dot.frost_fever = max( active_dot.frost_fever, active_enemies )

            if talent.bind_in_darkness.enabled and debuff.reapers_mark.up then applyDebuff( "target", "reapers_mark", nil, debuff.reapers_mark.stack + 2 ) end

            if talent.obliteration.enabled and buff.pillar_of_frost.up then addStack( "killing_machine" ) end

            if buff.rime.up then
                removeBuff( "rime" )

                if legendary.rage_of_the_frozen_champion.enabled then
                    gain( 8, "runic_power" )
                end
                if set_bonus.tier30_2pc > 0 then
                    addStack( "wrath_of_the_frostwyrm" )
                end
            end

            if pvptalent.delirium.enabled then applyDebuff( "target", "delirium" ) end
        end,
    },

    -- Talent: Your blood freezes, granting immunity to Stun effects and reducing all damage you take by $s3% for $d.
    icebound_fortitude = {
        id = 48792,
        cast = 0,
        cooldown = function () return 120 - ( azerite.cold_hearted.enabled and 15 or 0 ) + ( conduit.chilled_resilience.mod * 0.001 ) end,
        gcd = "off",

        talent = "icebound_fortitude",
        startsCombat = false,

        toggle = "defensives",

        handler = function ()
            applyBuff( "icebound_fortitude" )
        end,
    },

    -- Draw upon unholy energy to become Undead for $d, increasing Leech by $s1%$?a389682[, reducing damage taken by $s8%][], and making you immune to Charm, Fear, and Sleep.
    lichborne = {
        id = 49039,
        cast = 0,
        cooldown = function() return 120 - ( talent.deaths_messenger.enabled and 30 or 0 ) end,
        gcd = "off",

        startsCombat = false,

        toggle = "defensives",

        handler = function ()
            applyBuff( "lichborne" )
            if conduit.hardened_bones.enabled then applyBuff( "hardened_bones" ) end
        end,
    },

    -- Talent: Smash the target's mind with cold, interrupting spellcasting and preventing any spell in that school from being cast for $d.
    mind_freeze = {
        id = 47528,
        cast = 0,
        cooldown = 15,
        gcd = "off",

        talent = "mind_freeze",
        startsCombat = true,

        toggle = "interrupts",

        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            if conduit.spirit_drain.enabled then gain( conduit.spirit_drain.mod * 0.1, "runic_power" ) end
            interrupt()
        end,
    },

    -- Talent: A brutal attack $?$owb==0[that deals $<2hDamage> Physical damage.][with both weapons that deals a total of $<dualWieldDamage> Physical damage.]
    obliterate = {
        id = 49020,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 2,
        spendType = "runes",

        talent = "obliterate",
        startsCombat = true,

        cycle = function ()
            if debuff.mark_of_fyralath.up then return "mark_of_fyralath" end
            if death_knight.runeforge.razorice and debuff.razorice.stack == 5 then return "razorice" end
        end,

        handler = function ()
            removeStack( "inexorable_assault" )

            if buff.exterminate.up then
                removeStack( "exterminate" )
                if talent.wither_away.enabled and buff.exterminate.down then applyDebuff( "target", "frost_fever" ) end
            end

            if buff.killing_machine.up and talent.bonegrinder.enabled then
                if buff.bonegrinder_crit.stack_pct == 100 then
                    removeBuff( "bonegrinder_crit" )
                    applyBuff( "bonegrinder_frost" )
                else
                    addStack( "bonegrinder_crit" )
                end
                removeBuff( "killing_machine" )
            end

            -- Koltira's Favor is not predictable.
            if conduit.eradicating_blow.enabled then addStack( "eradicating_blow", nil, 1 ) end
        end,

        auras = {
            -- Conduit
            eradicating_blow = {
                id = 337936,
                duration = 10,
                max_stack = 2
            }
        }
    },

    -- Activates a freezing aura for $d that creates ice beneath your feet, allowing party or raid members within $a1 yards to walk on water.    Usable while mounted, but being attacked or damaged will cancel the effect.
    path_of_frost = {
        id = 3714,
        cast = 0,
        cooldown = 0,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = false,

        handler = function ()
            applyBuff( "path_of_frost" )
        end,
    },

    -- The power of frost increases your Strength by $s1% for $d.
    pillar_of_frost = {
        id = 51271,
        cast = 0,
        cooldown = function() return 60 - ( talent.icecap.enabled and 15 or 0 ) end,
        gcd = "off",

        talent = "pillar_of_frost",
        startsCombat = false,

        handler = function ()
            applyBuff( "pillar_of_frost" )
            if set_bonus.tier30_2pc > 0 then
                applyDebuff( "target", "frostwyrms_fury" )
                applyDebuff( "target", "lingering_chill" )
            end
            if azerite.frostwhelps_indignation.enabled then applyBuff( "frostwhelps_indignation" ) end
            virtual_rp_spent_since_pof = 0
        end,
    },

    --[[ Pours dark energy into a dead target, reuniting spirit and body to allow the target to reenter battle with $s2% health and at least $s1% mana.
    raise_ally = {
        id = 61999,
        cast = 0,
        cooldown = 600,
        gcd = "spell",

        spend = 30,
        spendType = "runic_power",

        startsCombat = false,

        toggle = "cooldowns",

        handler = function ()
            -- trigger voidtouched [97821]
        end,
    }, ]]

    -- Talent: Raises a $?s58640[geist][ghoul] to fight by your side.  You can have a maximum of one $?s58640[geist][ghoul] at a time.  Lasts $46585d.
    raise_dead = {
        id = 46585,
        cast = 0,
        cooldown = function() return 120 - ( talent.deaths_messenger.enabled and 30 or 0 ) end,
        gcd = "off",

        talent = "raise_dead",
        startsCombat = true,

        usable = function () return not pet.alive, "cannot have an active pet" end,

        handler = function ()
            summonPet( "ghoul" )
        end,
    },

    -- Viciously slice into the soul of your enemy, dealing $?a137008[$s1][$s4] Shadowfrost damage and applying Reaper's Mark.; Each time you deal Shadow or Frost damage,
    reapers_mark = {
        id = 439843,
        cast = 0.0,
        cooldown = function() return 60.0 - ( 15 * talent.reapers_onslaught.rank ) end,
        gcd = "spell",

        spend = function() return 2 - ( talent.swift_end.enabled and 1 or 0 ) end,
        spendType = 'runes',

        talent = "reapers_mark",
        startsCombat = true,

        handler = function()
            applyDebuff( "target", "reapers_mark" )

            if talent.grim_reaper.enabled then
                applyBuff( "killing_machine" )
            end

            if talent.reaper_of_souls.enabled then
                setCooldown( "soul_reaper", 0 )
                applyBuff( "reaper_of_souls" )
            end
        end,

        -- Effects:
        -- #0: { 'type': SCHOOL_DAMAGE, 'subtype': NONE, 'attributes': ['Chain from Initial Target', 'Enforce Line Of Sight To Chain Targets'], 'ap_bonus': 0.8, 'target':
        -- #1: { 'type': TRIGGER_SPELL, 'subtype': NONE, 'trigger_spell': 434765, 'value': 10, 'schools': ['holy', 'nature'], 'target': TARGET_UNIT_TARGET_ENEMY, }
        -- #2: { 'type': ENERGIZE, 'subtype': NONE, 'points': 200.0, 'target': TARGET_UNIT_CASTER, 'resource': runic_power, }
        -- #3: { 'type': SCHOOL_DAMAGE, 'subtype': NONE, 'attributes': ['Chain from Initial Target', 'Enforce Line Of Sight To Chain Targets'], 'ap_bonus': 1.5, 'target':

        -- Affected by:
        -- swift_end[443560] #0: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER_BY_LABEL, 'points': -30000.0, 'target': TARGET_UNIT_CASTER, 'modifies': COOLDOWN, }
        -- swift_end[443560] #1: { 'type': APPLY_AURA, 'subtype': ADD_FLAT_MODIFIER_BY_LABEL, 'points': -1.0, 'target': TARGET_UNIT_CASTER, 'modifies': POWER_COST, }
    },

    -- Talent: Drain the warmth of life from all nearby enemies within $196771A1 yards, dealing ${9*$196771s1*$<CAP>/$AP} Frost damage over $d and reducing their movement speed by $211793s1%.
    remorseless_winter = {
        id = 196770,
        cast = 0,
        cooldown = function () return pvptalent.dead_of_winter.enabled and 45 or 20 end,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        startsCombat = true,

        handler = function ()
            applyBuff( "remorseless_winter" )
            removeBuff( "cryogenic_chamber" )

            if active_enemies > 2 and legendary.biting_cold.enabled then
                applyBuff( "rime" )
            end

            if conduit.biting_cold.enabled then applyDebuff( "target", "biting_cold" ) end
            -- if pvptalent.deathchill.enabled then applyDebuff( "target", "deathchill" ) end
        end,

        auras = {
            -- Conduit
            biting_cold = {
                id = 337989,
                duration = 8,
                max_stack = 10
            }
        }
    },

    -- Talent: Sacrifice your ghoul to deal $327611s1 Shadow damage to all nearby enemies and heal for $s1% of your maximum health. Deals reduced damage beyond $327611s2 targets.
    sacrificial_pact = {
        id = 327574,
        cast = 0,
        cooldown = 120,
        gcd = "spell",

        spend = 20,
        spendType = "runic_power",

        talent = "sacrificial_pact",
        startsCombat = false,

        toggle = "defensives",

        usable = function () return pet.alive, "requires an undead pet" end,

        handler = function ()
            dismissPet( "ghoul" )
            gain( 0.25 * health.max, "health" )

            if talent.unleashed_frenzy.enabled then addStack( "unleashed_frenzy", nil, 3 ) end
        end,
    },

    -- Talent: Strike an enemy for $s1 Shadowfrost damage and afflict the enemy with Soul Reaper.     After $d, if the target is below $s3% health this effect will explode dealing an additional $343295s1 Shadowfrost damage to the target. If the enemy that yields experience or honor dies while afflicted by Soul Reaper, gain Runic Corruption.
    soul_reaper = {
        id = 343294,
        cast = 0,
        cooldown = 6,
        gcd = "spell",

        spend = 1,
        spendType = "runes",

        talent = "soul_reaper",
        startsCombat = true,

        handler = function ()
            applyDebuff( "target", "soul_reaper" )
            if talent.obliteration.enabled and buff.pillar_of_frost.up then addStack( "killing_machine" ) end
        end,
    },


    strangulate = {
        id = 47476,
        cast = 0,
        cooldown = 45,
        gcd = "off",

        spend = 0,
        spendType = "runes",

        pvptalent = "strangulate",
        startsCombat = false,
        texture = 136214,

        toggle = "interrupts",

        debuff = "casting",
        readyTime = state.timeToInterrupt,

        handler = function ()
            interrupt()
            applyDebuff( "target", "strangulate" )
        end,
    },

    -- Talent: Embrace the power of the Shadowlands, removing all root effects and increasing your movement speed by $s1% for $d. Taking any action cancels the effect.    While active, your movement speed cannot be reduced below $m2%.
    wraith_walk = {
        id = 212552,
        cast = 4,
        fixedCast = true,
        channeled = true,
        cooldown = 60,
        gcd = "spell",

        talent = "wraith_walk",
        startsCombat = false,

        start = function ()
            applyBuff( "wraith_walk" )
        end,
    },
} )


spec:RegisterRanges( "frost_strike", "mind_freeze", "death_coil" )

spec:RegisterOptions( {
    enabled = true,

    aoe = 3,
    cycle = false,

    nameplates = true,
    nameplateRange = 10,
    rangeFilter = false,

    damage = true,
    damageDots = false,
    damageExpiration = 8,

    potion = "potion_of_spectral_strength",

    package = "Frost DK",
} )


spec:RegisterSetting( "bos_rp", 60, {
    name = strformat( "%s for %s", _G.RUNIC_POWER, Hekili:GetSpellLinkWithTexture( spec.abilities.breath_of_sindragosa.id ) ),
    desc = strformat( "%s will only be recommended when you have at least this much |W%s|w.", Hekili:GetSpellLinkWithTexture( spec.abilities.breath_of_sindragosa.id ), _G.RUNIC_POWER ),
    type = "range",
    min = 18,
    max = 100,
    step = 1,
    width = "full"
} )

spec:RegisterSetting( "ams_usage", "damage", {
    name = strformat( "%s Requirements", Hekili:GetSpellLinkWithTexture( spec.abilities.antimagic_shell.id ) ),
    desc = strformat( "The default priority uses |W%s|w to generate |W%s|w regardless of whether there is incoming magic damage. "
        .. "You can specify additional conditions for |W%s|w usage here.\n\n"
        .. "|cFFFFD100Damage|r:\nRequires incoming magic damage within the past 3 seconds.\n\n"
        .. "|cFFFFD100Defensives|r:\nRequires the Defensives toggle to be active.\n\n"
        .. "|cFFFFD100Defensives + Damage|r:\nRequires both of the above.\n\n"
        .. "|cFFFFD100None|r:\nUse on cooldown if priority conditions are met.",
        spec.abilities.antimagic_shell.name, _G.RUNIC_POWER, _G.RUNIC_POWER,
        spec.abilities.antimagic_shell.name ),
    type = "select",
    width = "full",
    values = {
        ["damage"] = "Damage",
        ["defensives"] = "Defensives",
        ["both"] = "Defensives + Damage",
        ["none"] = "None"
    },
    sorting = { "damage", "defensives", "both", "none" }
} )


spec:RegisterPack( "Frost DK", 20241030.1, [[Hekili:S3ZFZnUnU(zzN3SEJ3nRJLsY(J(sYmT91oT917ANnxV(FXwXwow3Al5NK8MMoz8N9hbfLejfajLLC2TZDtNMKvIceaeaeaeK8gVB(h3C98G8WB(7(J9pZB8PJh57nE843EZ15pSj8MR3em7Jb3X(J4G1SF(9Pjz57M()8)cV5HvjbZbiKLSnDg7TlZZ3K9vNCYDr5l3E7OzjRpjlA92vb5rjXZsdwKd)7zNCZ13UnAv(pgFZTn7(XN)(tzDFW28LjP3C91rR)wgKJMppSO5HzZU5AO5V2B8RHp4R2n9VfMEx4UPqB3nD7gaK7MEpdl2n9dHlcMLNKUBAu8QO4QN)7j)(pegmF3pT7NQb2xPbdPx6)E2l)6vRsUF3080O4pgY4dBZQG3VM897Mopkl42vHZ)Vz)zs8lyT4(Gmax(qyWMW0xKXq1G0pQa3tzW97J(dwpNSDvzlvAbqHEEJgp6CLh7zaB9Gx(BcgXI0K1fnLHxldINVkKJVN8njxZq0WShINLv91JF)R9FhWtJIbUwW8)12S81HX5knX7SJ3nfAkjwanACjTTjjHX8VBs624qj48Ux7)gaoSF)Uc4nwa3XNl(D5ZFFr)0SBElBCRagf4e73NlG5z0FdNT)pwYye)EaJk)D2yyu8nxVkklpJlsZW2vHtYdycw5Sh835QkHX8H3B(gM85mqO(MRxaAetYyIeFmSq6mnAtXRUMddw3WbcBOnjpO4nS2KhMgfW0YcwXyTJcMSiKjPmjzXeMY0QSrIEA30bWi0TBxSyuAWFMKgnlCuwotPC30l3n9C(7fWiBzqoavgB(2vbZdvGbhcn6LTBUjNP7PrA1yh)R(y0k(y36GzmEKC37VB6JpkGD4FW(M1rXm(ma2k(tYTRaObk5SU6uYU6OEGohwGpmqbYz7MEbhfzF5ZQ(ygCVnnm4JHPsFgXOjdFpJeF)ua7xShpknAD4eaXZKrYM9tDNSm5(vcSplh6LZB3aW2nLevfsOOFrX8Fdz3Si6UL5tsdxhefZiJRQ54GK7OCGeZtMSzw(KtpNZxjF)yPpVyuG9p9RrjqWJ1tGroaNEljorqErZMSj5EMfsOdosQnPBkhfeYapZbjMcKSeMJMhUiAwuEHKZyUaLbHJ3zEydemkhRuqhqWiFjxlmkEEAWDjzb1OeG9IgYEvi0S8LHtyD(Fggpz2YG1ByyJA7NX4pZtUpgh0vJRdnid((onq8mojcDZeycMr(lviedQS0SxVXTfLclubLrdkDbpD75wbEj9AaHPnK2ADvpAlLpdCUiFurVVi8tm528OzFKbsddVE0wY0SvIQpa6WNVpsYvuDE6wMzYI2xkUYHBLSlZDVyau3hfNd992u(SL7M(AM7pNRj9k3uo9rBd1v01eTpUUVdsNfedM7stzW8g4)UEgJeMSmmi1ORcmDxMAi09rZ09v4Bzqy30FGdcAdZSbP7MnF06G)OCSqEWd43ptmDmXCgfJEQ6PLEhuteLZ8EfBQ3ZkGRZFYUPVRAI4Eet4GTLiIxPfCJ(4ulEuPbQyFTSl2WOJGuy0JR5vshgyDq)xqPOaaDu9L827TB6R4)HaZ4FW9pKUoBYITPpOGCv6p6nIjSp)HcoG0WX24LjREaSAfgFx(sfYq)DOy4qkbAJU35axEox58JXGi)iqUErcZ7IrlcwTcM4lDBgBMJQPBmnMuXsiz5xvysrA0X4qijNRITs85NAMFrBu2b(1ZAflZor2hmvzdLnOwAt0oqQMqnlJHN1TXW3R5JLj94tTYRpZOerUKFaqdmmBIK)cxp7HzvbRMbFIJHqCeAWBf0RHPEEjF6MHAtH9lsi(UPFndn)uOuqV7DGMvEM4Uv0bYXfufFMb3JOnC1)ywPWCHYlBMSjZdNf8q5ysfIFxWKnPrSqHZFOgZVBvWSOGvtcM)PGyCJi4zM4ZdfHiAIyiWgg35edu3gJjAH3lyjjbLk0dNgvX0MAioOPJk(ZxK66r7IRlPofMfBp0rYWTUGXz0dtLsVqnZsy6ufw5ieTk4BdLru8PAl)WYwAeEyDiLb2tLtNfDEoK9)VaDd4gENeghUoku4QtzMmW4OncZ2M2isuheixN1BhwAEXAciuclvtyqnIuD(ZLC(tZKveoxy1RgBiyG0PsOG8lYdKPGZ1Ny02qWx6Ce9PtDql1fscFQrumOTtkAnPpO9cThTvAiNAmRf0PKTcaELgORzfaynLrI)UNX0QsoveLakZSErQtoy(JkTMcAEv(n8oUT(tE4MMSEuaE6yYPlnUshOlEGdPVXuqqUgd1TjXH3Xm2YcmucadrPpzuvK8mogZmZNVmnmBjpRvVwovfoLZA28BVroZe7vkn7CgnpDSKHYI4GwZBfp1StUNnwYq6Y4H01aBWy2mzgFXXlIo6L4PmPPnakNHBLBKnqXgPV0fpyR7gDIB(dkJfmfRK0SWvHzzsuIrJo6Xgu5O3avXmMaWMvbXXLVtiwjcC)U0KTXZDiNTkP1WOQHI)lYKRY4wq8dtMhphZryN5ATynx0f2EJzZ90RuIBEGWmWNYNzoZKf(BxLKmNNBrnB0FG)TmB03gX4WrWQAGWuktGcZEq4SpA2(n1hvJlHm5VuUfcJgBTcib3CdlspxxXxkqTcM0jBY)A787wlgzODqWk0ahKy(PW8wAwWQvoQUsbSfrPH8HpZ6PUohIPCH3mfBsJAb3XNBGfnWhZmRlztT1YSHh1xP7UiuSQCe6ukreHVrt3m9TGKqx9Msrx7Rt(UcNHGKS9ZrQHCBY3bb3KnlqWNGxx4dmscqqYIdIUAhDOM3DDo(WbYEEqgLcwmoxWxzlI4xOcFXuQoi9FbRdOnY4M962wXi1Rj2yurmdzZQJHS1HKVGZ60nE1r5q8oHBwctvSUJTn9TloG(f(sQt7vbnbzWnLCOmoVBjxgWKPV1m6MPchg(N62((ra1s3UjxDolEiBczPzmfe2qmHrl7uWzJfwMKY2hBYtMOvW6Sja05JRqaI7ZyNtnCqRgJdIzitWDmQjBz4QvsdYkUVQ0OwyKtza4VXMRlN9)7Mkke4VhS1D8UP)4ShG6CCvcmviBQJDt)Ty2enSoBo02W4)8b3SxYPEDJ1xDzPM0rU5pVObqL5YIMl4(GhqFpPNffDJHv8JVY6KofuxGEKtilQlbgdEtA4SK13gGw6ijSjbYcZJwOiXxu(XJY9gTmiBY2SIuiOnDOosP5hNRsIaaR7VkwsTu2ZnWOQBfBeCCv4(TOVnxzBkyHz0Scb0x2YV7tbR2YmUdcUvajRUNpgkR7pfnhWPBzJ6f04UPjl4vwDwoRbI8guMy8ImhWEoua13ksGf0(Au)fs9WiM(d7Lr5WdbSjektB2FhNWGi3bt(Q4NgMVnLrkEqpUck98YNmE05J4rbmPOm9fuXeVjqTDxRBxAwb(lw3mbGYnxZ(AXdU5ApmZMssHyqsVx9f9kIeR)tSeR)FnKyrrtzjwJdx6wYfdxKd7nSGupXsdfE1HloR4lPxoSX7JYyZzgYS0gMMSnJfYvqC26iiWaCfeEYxX8jVfCrFZCrDHEfm(lHxQZf9Bjx0VMlQhyslnD4nPu(NycpZiwTsI0Na4Meyl1CohlQNwIU(MrxB8re013i6Qh8tlrxP1mdn(inTcDprvgSjKYRvce51N0uZWgrZGcFRwZpbfgsEbxvuLJoNxwLMudEPAeR1WdMrtgwLfOPk6fT6tR4bxjlXYF2qoI6nEC5YEmSCbwS6Gfgb65ebIyTKGa9CIa9qiqFscuvc3Rsu2hlXFokjppynS(sDrGg79YYCnOmi6dnwGrstpTaTyIeU9TGvS4zxYi5nB)Z)CfBSl5p68SCRdI3gScnQ(wGE(UHE2m710kQe6rebKj0tuIdbqWEfz2mjDnEC3rqYbMaLMz57LrO07RNiRrnzyhr8ERmWuxwqoi3dh1AXIQkrNy7Ynf2q88jrXtMhK(X4WSmmErgSm7ZMiv9K5iLvbqbPHK0qtEr1YgdrHTiy7QColagwYgDBsgRn6j8(x)5Dt)NcGUB6VWF8xTB6pa7e31BNb7XxizoWwALhdwEsX(nLf6fuKwSVrKuODt)gPyXUUYPCoLH54IduwiiZutDPr3DhiKxrBVDSJKZVLbdsf7LyzGcReTaSfK28WCET6cXzUmmgccSy)xdbWculFlkhgNS9ULfFbFxk)DLHO(bEiQ)opevoLJ5dulPCjKuI2pTJK(MdmHJ5nLdeopRrf0SiHYs08zosZfsVbXpuGxmsih2mY8MFplMuWC6dYYYlGCj8Rs5EqKbUc2MCTxdPtG9IiEceY5z14UTbmtW5HHhVBkSDUlEysWQrCgb2KXoWiOQiej2XBCv8)RxNSnoVGYuvNbYhKpyo8yqhUGvDldKfaUA4)dmS7gXM0QW1kJRX9MKIFRT5Sk)sj)mClVfK5hS09yhbHPktXnWu3kmyPmnbD(xjjNYTyuswHxun39a(NBoJ82YjRL1EUYNUSW458j5NNjLlxWteM5KWWIL38wqwcKUaKUYN7uE1BLXChj9JkRS75UqGEYl(XTj8Ttb7Fmzv06BXsttRwRBmYZC35qHmu6VJlmqbcgKodCliilduWvfBmncnSr6XmVnI0gzmTS7IDO4rIEx3pW6fvwEZC1ScMi2TBLOEZkk0tATuXlikhQ(JddZUgXMTK9EEjoe8rSeE0k9pxZcQrJEMmriXrrmsHLbeTf(gf1Qlje9YQ6mHCgzT9r4oYaPsGhTTkETn0kv5szWyLR7GvKNzz2ez66C31yzT(TIb3ooDNDwf9IU7aX7kRex9SfsVAeiAG3nW89eTgyBnhQqYbvf(KyTzHLzp(pFqDl5yAQY0Y9jKNYyfg5A8aw4apwzgZmUxWTAgrVgPR6FKGCLS7OSFz0HX7glnd5rwuJSRpkQTzlnUC3HBuEVPy(P1Rkg4cmVqiUOAY1uPTTGCbWHWqV5AiZKjlwmHnB7nw25iYUMP5fEHkzr6nuQE)5rcz1tlPZYcoscyteptELB6o7NU(LmCqCuR4LgbvNViHpmlFZcw9WMSIkoP03GQNojo5ERAenDUWQIL5zXnQMy3zzzJLCixFWfGMogmRhgyb6rWCz5(OPJrT5W0SUotN0isAq08jHFIttZNNnk8pGJHmHPcT3fPv(pAmpP1n4vn)yLfnqwszX9lK3gkiA9MhUODRCVgUuk4hBCsBIQuC3bnFvPjEeE(fUO5)A8Vf5X2hjmZWnUxlSZWTn)Bhz7fQjatP4OAj)(e(Fyp0LbiNWl257TsNdtO)ZQQO5rAlNYynzIstAgeXg7zEXnhDUwJh5xCGtFYZzTV5pjB2dSzW459H27xk)nL6iBhvc6BAi7z0r5SSqkrk1BZhFJoW6eAbd0cROwDTyGzwETcjBo9TI0Bi23ckt9G2b6UM4KEOCOF6u6SLGtnzYNcK21sVYaaRvhu1LbhGwLWOwrsAKn)yVh1hORiDSS3jnNCJ5JQ2((c0Y4UOGy2m0DtwE1YGIMw6YfkLyTu1uQRGp5huld7eZ7nAQzn9NS6Dyl1EJx6RTxxDYvufHlZb4Er5(k1I3NNQVSe)JYXaKuuxZu5THXMZwLKl)VvN8vQyoGZrKIiKUIxmFy8eB1Mq5I3xYXpYEjmy2582Y7P7QH0EbiR0Jqskv3IVQ3Ws1rqZkks6Lsg5LCdOrNvVLtUSmQu0HEXXbS4Zkxyn(QYbBBHqyvZy)iADqoWz4lq)XLlwhSWtB5lJjFZciQb(nbrPWZeNq0CwK0I3ncBvb0K28PKU8Dt6Y3ALV4K0L3FHKU8Dt6sVE0uKU82lPRcJ8kwh8Xwkg7wu0nSpdRwiDsaOvMxS7rqBgApuztJYnkzPI3y1PeRP)A4tRzjI2jBReCKqBYSbfZZPVG1SWNId5deaNQc)YAAVQQgzQwJBKfUQPrjnHCxeypewS(pcSoiWEGS0rA)2jbwK1I0UzXzDQkp19KQQbevvQ8jHuxTbmunb)wSI33YTIgPlRwEmxyvvQCsDdyTSKNz)(Th5HOcagQ7nHPe7yXJFO4mu3lPmRIjXREa(zi8dr9cjqzMZBPjWU(kJxRua6FCzlaxctGImO4ZQONDt)f2JIyaoomQ492H2Tj8IzsgoyRZTf3c7Mvux1f8r1fAT5fkDb8ji(sxxabRnQl49fHUqdNuZRlkf0mryVwLXwZfnLU)zvpOuPXvjVdl8723XxX746oqknCyrCzVdK1pus1OYeGkz7BOcfkTY0iHdyhb4cJA3NesyKwLAlubflcadebXZwgsS(6u1y0a7hpd1eOAvItShWmqFcCPrDjiJnLor1Oruz7t(yBPXhvtl1h0McSiA2dtY5BLD0(x61U0ZsnVUppI3MInytXzfMOVZwNuw9AmVPdJZupmmr(cOg(BGUfwyvhI2uparSR3SpaTVlg0r7SUItwDq2BSUjqCy5ULYYE9l7ARvEqSC6I6Jqld7iqKC9Ao7PxzF(in75FFskC9UbvRDWgMlobZevEVuT6ZDxQy2XYynzpcC9jO84cd6x49jqOQ1osKVmix891xJCS)EzYwi2kM6KYU9OA7aWCe7BzOdWXba4DEgC5VjGeBGzsHy(e4Y(c2CiRwPT55BEKBqQAi2cy25BcfjNgkWkjqh3GCfBoHYd6gGTlliOxNJNkF6pFrPGOnIzs4FSjCgplOxuugSYSItLN28OwbTxvMjKtuRa3tkDvSarRA2lLEEnD9QY14AyzJ8gpgR0bDKLkgPCGNQCsY41i)gyNKlimqFngOfiSFmnDoM)4M8R9yRc2SQyBUBz4SfBth0sV(TWJKDlVfYJnPdvHGAze170jSYF0oVZjIDGlIex0m8gzeVGLHxzFftM5KvkD)M6RXsh78RQkfXbnlGBHHnBJ175qC1Hhgw1KAFGwHFqEQ1nqVjrXyN)Dy(tCw1qJZDvJw5EV5R5PP8HZnwjDANbrwo(15yL6O2vmBwvnG6Zfuua4jKaeXQFXr4kwDBANmoYMxTYHnigTerR0XdTY6r)sTU6d9zw8CXvxFNLqf)qHM(Tu9AvMpWIjVaPmEOpkC52XlBHAHwJNV9pZuWWAnGiAyvlDgVodRfHQlLpE6vk3uKLjxPuUr58URwadjviARXtsc4fD5zbAH3SG7Wmgwn0b3BLD4T4oUvGHFQkFmgwjAJqOCHLmTmNgbq9rcOH1DYieuw5kQ1uWiekp7JrINQXM0q6ADQ5CCCjBQtNBNMauoXO9LMIdQjdSOLmOfkjKzE8sIBroZdUv3SIibfPvlKe58TUR0c(tPNk(yS4eCFlgzkhiwsmTBiPYLdgMl614k6u1oY1HdNymNyPHErYEDc4mYw6Q1wCYG(PW0m4tRUi4V567dsHSSYIDMxyorR3KKMl2i8VqbiVac())BBrX2KXtLqW28erL6mBzq8Dqwb(PFMNqc4gl)BtIz9i)1VOuQw7EF6ffgtPED54oRzh59hdTbD9Pm0Go1mk6q)0phqV(0erdUnpMr0H4z9oeF7bLd8oCOJPZQ1dMmR7yVKsFkVO1zgAjvF((dkFZJyGUNzCENFG7MD)eITM65GANHgFCKv2gUgsInXIopGaQ85AQ36aAaw7TT0aqhXyczJocvcrH9gQOd9AqRfd(eOxpPVra9(AoSXhuKNc8AENQbDcFxDf4Aj)ah11tnsdGtO81pyobW7iMJkxxynSDs0hgJdeq9GoxiHpek3XqA9c69pKJWDV5qOdDvXS3UrpcJWvX6PBQqpgqhnQRgBOoqrdC0rBB6lHFJbi8AhWrOxVm9Vq3Ju9QbWri2CP811CjxRFh7bPL(xd0iffGomFdom1cEvdUeRbUJWEV1d(ma1djF4qcBK6pqd(gQqb9(qloLKncEPy90FXrhzBbwQwmTx5n85IK)m85hDe05Sh9s(FvMA(xD(WHdFP34XLyC7G)jLW)eRWFeruriuOXLAJIQK7u)X6eLnqIsiOG0QxpDu5GcS9w8wIUHiPjprDtxzspry)HX9qNaEN94)VY4(PwSriPzEbXcl(s)xk0PhOU6Kxj9XpN4JlX7(QFoHQFQjzcN76NWC6Bprjby3DfLc0Dw0c1ZEXYq9Iw5xFFhZb6m)DgQO0B1s)1okMqDVNn3(00lpPXulDDyPbuKlklhH5EJPOsev3fwTtIOXeWI9MH69Fqf6LQSXvKETQU)b059NipgizlvUvxUv9q4nyT5Gc()d3zF4onChHq8EWrMfrh8mh4HmGyahF(ZjdxRSjxoE4Jp6uhzUkaR7stieR3gArR)PGT80ZvSYuONMt8L(MnD241Um3zVy68PzEzA2IDTx82Cqb))H7SpChAtN(huBei44NxtNiieQPZNE2YtpxXktH2JyfVol)yI5FKETz3Sva6E6kRzGYRkTY6jMaY6TPNbFhq81bzSGmEWeEx3K(f4DaRzVlJjsXcqYiMR2S(Vt6afSeynMW9Yg0NaUd4lu6IMqxX77rW2EKL(AtdPlm2yLoSrsSeaX3SHQgVUfaDpDC0mqnBjbVn9m47aItzlbTj9lW7awBYgczZ6)oPduaU9eKg0NaUd4lQfLMVVhbB7r2wyOYsJv6Wg15qLLXnPjZgXp1u3KzkVjuTRN7gGBnP9GVfST2yFVrPauno5g9q3UEUBmY2ObFlyBTrARXkNOO0SNtlsb0ofuanMUFbeFGbVda215BnoDE3bpLLpAid3(VysDfp2jG4HdeVwce7JnoKL6(g8oay7JnoeYz3bFBh67LrTUi)0iBvptQoI4aQ8OfBqJxion4us2ISbNhF8zeMIg(4J0qZCUBq(UY3n8Lh5n68xrOnYElY3cxq5W39kLUfyCVwB0y4Z9gpE4WHxDK58YJW)OqqpRiOhkc6PHG(kiyPGWx4JKN85BK8eNgjBIGpzJKceS2WxJkNq8bTs1NciTYiuJD8vnqqVf3XalvdDVJC1ZT24WBZYsSMj7gPzOHTONCL2AJxPuvtO21AAvFG(wY18MAP1RVx81amYnMFdG(5ylCq1PDyNLsbs9Bl)gCi8lt)AWZl0LfjRwLCFeC8hfWmnXMe)(q4SqBl)u4U64jlq50C42T5LTJFvEVa29jYTE(COXZdYdUnil8R29t8lBkiwFY9YyHTZwwLzFgkgM)Qc7ETc8pmBH0(UwUkG6HRmmP2TJDhYpP7PKEEv4)SUx17ihIaQ9IEjXoDVJymbu7zU9N5nCrh5rpv7ecklnk33H62dqVmeDf09nfqzrRhOacq3lQwuaVRYnhuCMWACFWRpKBWppIk7VpW7dZMgGcShu2rVaCFkF50VRf1ap5DXORDG21BOg4jU8dDf46xsHAqN6omSg8OrqiIQTFcGONTRsv5Gs3xjvqxkFssVZfVVFIq6oTououdLITqlcGrAYbe4uGTzcVXgZUACZKKwM9uS8QwCTNm4OJA(YYSHYx(a0rWTBG8RAFiMovRdlGoX2z(kdjY85(dhC0Zig(F8rdCyeSP8aA9sV6Kq)V1C3touC3kPBQY(Y3GTjFABtujRQFTn9exJRwnFG2KdiWPaRbBt(M1E8j1E8nP949fO2JpLTjpkTNMCytAp(i2M(3rU7jhkUBL0nvLETN(n90ee9tCzTA18HD)M6xGxbwQcoBpNz5qFglAgP70ml0a1kd2(ml9lWRalDDV1bXyAGAfxTlg3Va3ky3tJqpnjH)PbP7LKC8KwAI7NsXbf4wb7EAVKiXu9SG2tds3rbn0egjU3dErRYxeb(PCu8kJAnpw(DKIp0dtfGOxo5COsi8(EW5qbVUVSQ99sWHkxfKe2ozQdvAslG(H9uO6qEaADOxAZD)0pYh4aG75RwJlWOZnxVjnzreCZ58FTB63b3EoSbWm(vLSWwww9D50X7MopcUlLzq72h2nTWOeC5bYemaYK1arfwuE3NvuJfSNdYnf4Cr7LiSmLlYz42HokhEi)U8z30Lqf7eNaYBWSjZ5apmFBkJo8GECfCxSu(KXJoNrxf0z2OQt1MxDzvLkEmCxiCPG6eLC4XjBUKFF0DmVtV0746RfUlzG84zjXZJayEP6C322r2g3j21LskwnY29DGTZ786NBapGDEDByO(7ld1VpzOyvf9NdgkXwzVnmurgsemsCxhLLKK5I1POaP88rFPy7mI(UpvVzbrF)s4BrFduwCdLFdDvz2gwJpkRXNG14tWAq20kOVSbRX3cRrFhlI(gnwJPcwTnSM68R3qv8CzDX6He0TsgQHV(bd9BjgsSz3qTK0pyyzc70XpFz0Ztcb6YUjGCZeSp7LGUTPqquiCE7eOTBci3wiDBxHGynZ59tG22jqDFH4I4X8G1qvtFaKsOx6ovS9QlvjgxW66(QiB8nMpbVS8pegTrraQ9fq)zAm9E1PleragOu)(1Z)xx(9UaCH)aId01sdzV1LpnlpacSR(M8xfbtPlr)kKTUe7LWF1IJF3pX8W)R)1FE30)PO33n9x4xOHSyq(HK73nD9w4oe)dWXv7UP)AHx8qihf3X3L3G4qEn41s)3i5n)1v(a5cbxZRYxMgMTKXIpwKQcqdcaF2OBtYyTauQynjm3i6)B8k5hoknzHdadZIoaQYBM0ZD3vsksxo63Vmmw6MlNfYdqDRagryCY27exN6BHGl(UYGA(apOMFNhuJluQmYSPevQO13oUBK3MVCiojoDf5DQBuxHShBA9cmGHS8nybV53ZCuhIe9bzjrEoi(vPyp)EWj(sg0ViNodw4KSxeLj2ehSOAVBBaZQrEyilYX)12mXdtcw5uuJ8CLOCLAxrTN5g1(1Rt2gNxG3QQAaaHX5I6AJu)IZiUfs3chWvdJFaUEPDGekhXaRnOAGVrwQScIm4iDBPYjrJxdQYFO(DsybIuIwz2BQygahAz1bBS9Mw6)HdqvC8qBVH15c94Ofx2ibPdo6zCFwAEpLAmSZHmp7qVrsV8CMFIwUhsRcywlvNvpVkzL1prjtJmpoH7v0bk3POxC5DZMpuMHOD3zklSb8ctRVVvWiNIsjgR8JXxI)TBg8mx7z8r0GKqOhHNxFPBE1L(2)swhvFpz2egx6bAxGLIKVRwh6NbDOkTywNZaFfzgwXiBkanGiNPf8LczKaM(78Wzbpit5IoHZVeF0XZEywfMZquOBRDnf52yFaH05aIuTwLChT0K(4JQ8OloBOoEUm5(vc4Wy0yi68eXLU3KfHSWYhXeL)iyq1iGkzSGzreUJddbCs(QX6FPMwx7zT1r1iD7U)4JOC8loVb)QtJR0SHMCZ0yq7QOCPbadwIUWFGe0ysHlIMfLFL)5qr1qBVtje3M3tlxvf5OAVwfi5R9AYhy20caFusszHlMlqqemtOuwo57xZLhzZUMKZbDnylqkvzde(lTSIKnKAGbxoGmBSbBkyIk2CVc0NaqxD5sSzw(Ktp)c0NpM1Cjs8QZhJ0DnucQL2QdhHnhdLrhkJUygOfgIrUU7hQGO1OaLRkV(i7Hg9Y3mCim5OnJbsSIwibF64YPYX2rPW05T6kdzy)iwP1V1s1yd9mHQK0SqM)xzs0SoQo)bCUfplCXZlm4Qn5IGhlz5IX(3W8XaUtPlfnuUv)q5Xx6nUYJezbjjRdYijgpSH4TZKNjRfx8gNuLuNpPWJzizct)bWvWAiu7Ei4kXsqthKdzg1Byb4cM8YGJkKlnOvE0ZGwpzjBizK)YcLuPvPVyMQlp7XhDOzVdC)Rl9Z7CQB8uwueZSemHcslreept26i0prItZtBOOV4VS(w8Dq1uqAVG99bZFyyjttiLxThLkri9Nl1RDJnqemWcMhQGXX0Tzm3Vsf2IryxKlrw5CqENlyCO8ucIwWnq(Kt7g5sf8Jo9sJX7pNq2QQzuNE2qK(LK7Ew75UV)XhTrgxCkjZbC(wy2sps5QK3dH)SjbEg37bI1SLGwRRRB0pGAQvQpQ85iFNEGfSa4Oqk8WDbhdXO9GBtwhfZhszH(T(whhU))7UJTDBBKRFlgbrRODITivKtBHIEPalAEOxqRxSVzBAjkBvtlkikVo5f)TVNZCJZTZmdLK3gueGabAXzoZzo3VPUR7oDKvRxWc48IwqWkgH7BGR4kURB3H(oHb3vR06qBeBbXXBFuDxoXpWN3dG3lBMpG0)sgXQczi4Po2EdaHutNN7Qbr)zQeyttGja0fY57SNMpCl1Ls2CpD6sUzwYLzI7bfB(ruGs06AgxC5JgOOddH4FZ8WrqsOgWVmA(yFCmehCcyHT0erPzG(pbNt)0icRR9gAC2VgF()oAXSUF4TG4i)6PciqJdHtItkp9Zcj99qskXbZ6BTxed(Oy7fLanqK8(niC94iGaPItRFMQzwWsjOfVuMLNo6Z)1EFpp(3oFV(hW6yPz5YBabpIi5eKfs3dBp(JQ8TUZ9c934pncJbnjXxmkxWF5GFj0Kzc6jtsPXybAnedZXuqMmdsPUJ0vq6Zd6HiLkg2DJiNSyfCRpotfqtTf5gXZWnGW5HKWftiaylpjqySJ4C7kmGjn8qD0nQjKEtBo8jIODTNI2dqvryReb)UNd4j(HFtJ1(sozXaszvL)4gqjJeqnBlxT4MQFJbllw0EE13WkKfycSE(kTOpADEuHF8m7xsvelDxmlFzPm4Awu4hxChAOBprEUhAoYyG9JrPkoONPXO))O7748OqiSdf)4toDpXqd0I7XUxAyFG2MSbgH)ig6javQlU4pmcxcrSLRaKkO3CHR2icKrGBV25FheU1PjZtaNOqXeU30fJs)A5fRNBYXg4nYLH99s4aWPfrbM47kI8fsei10mGcjjjMDMqoewp2PxkanCNXP2W98hqnOTFPibvFKlIKqRJ63Aa8eLVPd)NzlsnFciH3sS4evc3DsyQJauEyqE3R3(3wHfoZ)sKdozsBBzfOZR3oT81BbROw(LF6HD720(xU4IxE5LZFP5LhageGw4PlA3uvxdoto6YrxWSR6JRwV85wyn(PzIIa5RIhm9IYzyz8SQUhR8K8IpNlmo9Jnl)idbbln7bALkdFXXQI55nF41B5tevSqBWpL6MLpPO4Z)zHTP4UP1rhZ8x7k89fREhmv3YBuaswM(22VZyjoZwtDP37tuPAkXYPPQwWPxKYbufLcihy16FR5rG66Bar96YAMCCE9cW9nusrWnrTVE7Py(nn8jQHFe23fEWl41kRmwed)kYZU95nAP5qhjOvjrCV(y2GlSVwuGHgI11F5Y1GX6L3d(MaoZvxBLCgv6J(0iZGHVC1wqyEjOZd3GPOb)XYcDsEVfod1waRUgvan93b5t7kXPyIOe2(zmjLal5xNdIxUQSMjDHre)lsVxXVl6(QFKJtwOOYaQp7e9B1S4HA)qLREMPruNe2dpYGxmGsFFMma0610xOCYRdpNTNPqvOWLXGYIokpVQo5H70ImYn2FUa9wfatjceT2onWto5j3A76n5G384wROvxkKGfNcKUmuEBGX9gC6B9mjD1a4XW2(gfv08CTiWt2pneGTxKSKR2rVAsQMvKirVVsnIKJJsifnhwcLvvplCkek01xS1Tsk9xeMtN4UO6YjgJHSsRUA2iD8NhOTmBjX5z0h7y0TQG35z76jnD2Gi1LMuBH1vHDQ2(sUsDHv1(1x5No1Mxpro)V78Ka1AyG7OkRnXs(Z5oXB9rnM8f8wdnvtZ1df90XJsNiGs(HWiH)ndhdMhCh2gMR0QR8Zf1Vngk96MMfQqePqeslxUz(dvZF07lco8xTffk1ZxuGg2ac(R65RwJcIAV5)(8I7FsGc7XBJuAaraq2H1NCpFzWA5kgUQNV3DL3JejaT38hB5227APizugyp3TahsAJ6vvbnKyNIwDoNooCuues8fKKGJI3JoWFfJ9ZNfRgfjUnVBh6ZXWIEkmpbdrSHenlrcAFgg4hpwmN(rKQ1givmbQt5Q5uoG21(Bz07lDXa2zw9aNf8GqqOVn(e2QlBYEzFBTzl2LrQ1IENzfk9Mo0CE8kFAHrD(f9ksxVFIERhSDjvEOgkDXbaW(HUozOEO)TnBOJGovAmcAjJemCKG9deK6XvC8s02Dj6rLA)hBVgydQU2afmGAEpaJektUYUj4KnjoQoeZ)cCT8KvIyeDpN3wMgHMOrv)sICjRH0sBqheouIjYzo9s)zCgTI8Dyex)vwFVITG48MN2uxTRs0nPxTvIcyFw1243URS9XxV9EWa)1NBg1wnS7cwYJ8HeVbF)KZ(LBMjmVzVLnRTeBSSHwzWpgJVkmcHW)TsmKTyDj(hKnjl2sO8FrZyr6ue2WnL8j0fFPCIs(5HjMARB2jB(sURd7uddGFmhu5hVHam14FNA(K33XtE6y(cdm)pQJH5JhMNA4wtn9L77Wxw08YLRxxXA4Ae60h3z28tQjFGyxIib2KPXr0WXJdIozTHVNowfkwWgOy2L7xfFL9wWR55V2XEpZ0g7bO(L0VHlOVHpCo1)))g(yXt7v6t4B43XN1GnRR)o()v8SsZMLcILauFUTbN3H8bIiIm(G8BGkLBWmIzMm7ZF92)5wEgTxxTI)3JVA31WsTSX6KmfOvm96HaKoR4igPrySo3hUr8kEOFbDhcLl8NTPx5T(hjJIXy0sdmqsqAlvJzvmytEgDo4J2cgXUql8FHMG8I4xOf6xOPZ8zCHw8JXfAr0l0834luMme5mErtNHeqWBy5NLJ6jv5KjgYt47youiIVkALhM3vzwsRIMizXQ4THD1KSQTVzPSdot0k2LQkCoA7wP5aWsfQKyZMe)Xb1ymiea824BCBz3MaQyfB19aAb8Lv3zJvT8P1xKdsJZ0gwxFhCBeRTdXA39aYvv7RWxVHJpByXPYik9uJSTLalrQw3wLP9xXjaM4LnMWD0ygZ48BIFS4oOdXEYXJxYeMpQJh0OKI(HSpbzm))CZ2NEUUeNItLBa17LZFWzwCXmvaLs15jb8Ow2eCsMPkmCfObfOJisKp(1k3jE)2v4(Gyd4Zp08m2h5aHGXeAtnUVaJq(Ra4G(UGlq(KwTF4Y3AoGDWb6wT(WVIMQWx8XSh6Hjfgh9bJymrZAZnXKw7zXwWuoPmQp5e(IPHX(ComA3ADt132unFx1IZYZEVS7aF)qwQlGhD6q9MA7SjaN5P5JgPJAgRD2nYzkpS(tlIwuSkyyQEBisFUfi2WhCn1SU0duhw9ZkMda7ZAH)ZQkkO5JcxXDjEancsT4eT1Obb5x9mrcIVS)ogi5qH4jMYG1kPFZzbz63n98elrQMYZ9gi6WxYod0eDGYTLTgCssCUzuLv4Hh34zJhLnWIfk2nWHI41QudjRJvMYK1nczsBT1f9Pm30TPweY0W5Orljta0nhVJrXTPB7IBG5iTHjIsLoYIzAV87jE5ualvRViXPHSOqAfLS5U3J89ZeKHTCOGgSB6fb2CU(rP5b(MQru)f7v3T5eYjlwReg3F01X0j2gvR9i7j(hbXu21)NwqU01)JIj5xVd(31)(d]] )