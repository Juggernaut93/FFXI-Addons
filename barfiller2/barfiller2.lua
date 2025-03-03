--[[    BSD License Disclaimer
        Copyright © 2015, Morath86
        All rights reserved.

        Redistribution and use in source and binary forms, with or without
        modification, are permitted provided that the following conditions are met:

            * Redistributions of source code must retain the above copyright
              notice, this list of conditions and the following disclaimer.
            * Redistributions in binary form must reproduce the above copyright
              notice, this list of conditions and the following disclaimer in the
              documentation and/or other materials provided with the distribution.
            * Neither the name of BarFiller nor the
              names of its contributors may be used to endorse or promote products
              derived from this software without specific prior written permission.

        THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
        ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
        WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
        DISCLAIMED. IN NO EVENT SHALL Morath86 BE LIABLE FOR ANY
        DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
        (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
        LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
        ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
        (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
        SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

_addon.name = 'BarFiller2'
_addon.author = 'Morath'
_addon.version = '0.2.6'
_addon.commands = {'bf','barfiller2'}
_addon.language = 'english'

-- Windower Libs
config = require('config')
file = require('files')
packets = require('packets')
texts = require('texts')
images = require('images')

-- BarFiller Libs
require('statics')

settings = config.load(defaults)
config.save(settings)
settings.Images.Background.Texture = {}
settings.Images.Background.Texture.Path = windower.addon_path..'bar_exp_bg.png'
settings.Images.Background.Texture.Fit = true
settings.Images.Background.Size = {}
settings.Images.Background.Size.Height = 5
settings.Images.Background.Size.Width = 472
settings.Images.Background.Draggable = false
settings.Images.Background.Repeatable = {}
settings.Images.Background.Repeatable.X = 1
settings.Images.Background.Repeatable.Y = 1
settings.Images.Foreground.Texture = {}
settings.Images.Foreground.Texture.Path = windower.addon_path..'bar_exp_fg.png'
settings.Images.Foreground.Texture.Fit = false
settings.Images.Foreground.Size = {}
settings.Images.Foreground.Size.Height = 5
settings.Images.Foreground.Size.Width = 1
settings.Images.Foreground.Draggable = false
settings.Images.Foreground.Repeatable = {}
settings.Images.Foreground.Repeatable.X = 1
settings.Images.Foreground.Repeatable.Y = 1
settings.Images.RestedBonus.Texture = {}
settings.Images.RestedBonus.Texture.Path = windower.addon_path..'moon.png'
settings.Images.RestedBonus.Texture.Fit = true
settings.Images.RestedBonus.Size = {}
settings.Images.RestedBonus.Size.Height = 32
settings.Images.RestedBonus.Size.Width = 32
settings.Images.RestedBonus.Repeatable = {}
settings.Images.RestedBonus.Repeatable.X = 1
settings.Images.RestedBonus.Repeatable.Y = 1
settings.Images.RestedBonus.Draggable = false

background_image   = images.new(settings.Images.Background)
foreground_image   = images.new(settings.Images.Foreground)
rested_bonus_image = images.new(settings.Images.RestedBonus)

exp_text = texts.new(settings.Texts.Exp)

debug = false
ready = false
chunk_update = false

local is_hidden_by_key = false
local is_hidden_by_cutscene = false
local is_hidden_by_zoning = false
local hideKey = settings.HideKey
local LOGIN_ZONE_PACKET = 0x0A
local ZONE_OUT_PACKET = 0x0B

windower.register_event('load',function()
    if windower.ffxi.get_info().logged_in then
        initialize()
    end
end)

windower.register_event('login',function()
    initialize()
end)

windower.register_event('logout',function()
    hide()
end)

windower.register_event('addon command',function(command, ...)
    local commands = {...}
    local first_cmd = (command or 'help'):lower()
    if approved_commands[first_cmd] and #commands >= approved_commands[first_cmd].n then
        if first_cmd == 'clear' or first_cmd == 'c' then
            initialize()
        elseif first_cmd == 'visible' or first_cmd == 'v' then
            if ready then hide() else show() end
        elseif first_cmd == 'reload' or first_cmd == 'r' then
            windower.add_to_chat(8,'BarFiller2 successfully reloaded.')
            windower.send_command('lua r barfiller2;')
        elseif first_cmd == 'unload' or first_cmd == 'u' then
            windower.send_command('lua u barfiller2;')
            windower.add_to_chat(8,'BarFiller2 successfully unloaded.')
        elseif first_cmd == 'help' or first_cmd == 'h' then
            display_help()
        end
    else
        display_help()
    end
end)

function bit(p)
    return 2 ^ (p - 1)  -- 1-based indexing
end

function hasbit(x, p)
    return x % (p + p) >= p
end

windower.register_event('incoming chunk',function(id,org,modi,is_injected,is_blocked)
    if is_injected then return end
    if ready then
        -- Thanks to smd111 for Packet parsing
        if id == 0x2D then
            local val = org:unpack('I',0x11)
            local msg = org:unpack('H',0x19)%1024
            exp_msg(val,msg)
        elseif id == 0x63 and org:byte(5) == 2 then
            local flags = org:byte(12)
            if hasbit(flags,bit(8)) and
                hasbit(flags,bit(7)) and
                hasbit(flags,bit(6)) then
                set_mode(LP_MODE)
            else
                set_mode(EXP_MODE)
            end
            lp.current = org:unpack('H',9)
            lp.tnm = lp.total - lp.current
            lp.number_of_merits = org:byte(11)%128
            lp.maximum_merits = org:byte(0x0D)%128
            chunk_update = true
        elseif id == 0x63 and org:byte(5) == 5 then
            local offset = windower.ffxi.get_player().main_job_id*6+13 -- So WAR (ID==1) starts at byte 19
            cp.current = org:unpack('H',offset)
            cp.tnjp = cp.total - cp.current
            cp.number_of_job_points = org:unpack('H',offset+2)
            chunk_update = true
        elseif id == 0x61 then
            set_mode(EXP_MODE)
            local packet_table = packets.parse('incoming', org)
            xp.current = packet_table['Current EXP']
            xp.total = packet_table['Required EXP']
            xp.tnl = xp.total - xp.current
            chunk_update = true
        elseif id == LOGIN_ZONE_PACKET and not is_hidden_by_cutscene then
            is_hidden_by_zoning = false
            background_image:show()
            foreground_image:show()
            exp_text:show()
            mog_house()
        elseif id == ZONE_OUT_PACKET then
            is_hidden_by_zoning = true
            background_image:hide()
            foreground_image:hide()
            rested_bonus_image:hide()
            exp_text:hide()
        end
    end
end)

windower.register_event('prerender',function()
    if ready and chunk_update then
        update_strings()
        update_bar()
    end
end)

windower.register_event('level up', function(level)
    update_strings()
    update_bar()
end)

windower.register_event('level down', function(level)
    update_strings()
    update_bar()
end)

windower.register_event('job change', function(main_job_id,main_job_level,sub_job_id,sub_job_level)
    update_strings()
    update_bar()
end)

windower.register_event('zone change', function(new_id,old_id)
    update_strings()
    update_bar()
    mog_house()
end)

windower.register_event('status change', function(new_status_id)
    if is_hidden_by_cutscene == false and (new_status_id == 4) and (is_hidden_by_key == false) then
        is_hidden_by_cutscene = true
        background_image:hide()
        foreground_image:hide()
        rested_bonus_image:hide()
        exp_text:hide()
    elseif is_hidden_by_cutscene and new_status_id ~= 4 and (is_hidden_by_key == false) then
        is_hidden_by_cutscene = false
        background_image:show()
        foreground_image:show()
        exp_text:show()
        mog_house()
    end
end)

windower.register_event('keyboard', function(dik, flags, blocked)
  if not is_hidden_by_zoning then
    if dik == hideKey and flags == true and (is_hidden_by_key == true) and (is_hidden_by_cutscene == false) then
      is_hidden_by_key = false
      background_image:show()
      foreground_image:show()
      exp_text:show()
      mog_house()
    elseif dik == hideKey and flags == true and (is_hidden_by_key == false) and (is_hidden_by_cutscene == false) then
      is_hidden_by_key = true
      background_image:hide()
      foreground_image:hide()
      rested_bonus_image:hide()
      exp_text:hide()
    end
  end
end)

function comma_value(amount)
  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then
      break
    end
  end
  return formatted
end
