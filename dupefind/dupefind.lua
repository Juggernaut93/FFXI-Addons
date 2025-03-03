--[[
Copyright © Lili, 2019
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of dumperino nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL <your name> BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
]]

--[[ --------------------------------------------------------------------------
----------------------------------- README ------------------------------------
-------------------------------------------------------------------------------
dupefind: finds duplicates on current char/across all characters

usage:
//dupefind flag1 flag2 ... flagN

shorthands: //dupe, //df

dupefind by default does not display:
- items with the RARE or EXclusive tags
- items that cannot be stacked (with a stack size of 1)
- items that cannot be sent to another character on the same account
and will only disply items on the currently logged in character.

flags:
- rare: includes rare items
- ex: includes exclusive items as long as they can be sent via POL
- nostack: includes items with stack size of 1
- findall: searchs every available character instead of just current
to use the findall flag, you need to have the addon findAll installed, and have 
run it at least once on all characters

example:
//dupe nostack findall - will find all duplicate items that are not rare/ex, 
                         across every character
//dupe ex nostack      - will find all duplicate items, including Ex and items 
                         that do not stack, but excluding Rare

Changelog

1.0.2 - Added more ignore options.
1.0.1 - Bug fixes.
1.0.0 - Added POL groupings, fixed finding of EX items.
0.5.3 - Added wardrobes 5-8 (how come nobody complained all this time?)
0.5.2 - Minor fix.
0.5.1 - Cleanup and better help text.
0.4 - Some more cleanup.
0.3 - First release. Many thanks to Arcon for the feedback about the code.
0.2 - Cleanup. Multiple character search, toggles for stackable, rare, ex, CanSendPol.
0.1 - Initial version. Single character search and stackable toggle.

Thanks to Zohno, this addon contains code taken from his addon findAll
Thanks to Arcon, he took the time to read my original iterations and letting me know all the dumb crap I was doing
]]

_addon.name = 'dupefind'
_addon.author = 'Lili'
_addon.version = '1.0.2'
_addon.commands = {'dupefind', 'dupe', 'df',}

require('logger')
require('tables')
require('strings')
local config = require('config')
local res = require('resources')
local lang = windower.ffxi.get_info().language:lower()

local default = {
    ignore_items = { 'linkshell', 'linkpearl' },
    ignore_across = { 'remedy', 'echo drops', 'holy water', 'eye drops', 'prism powder', 'silent oil', },
    ignore_players = {''},
    accounts = {},
    move_items = true
}

local settings = config.load(default)

function preferences()
    ignore_items = S(settings.ignore_items):map(string.lower)
    ignore_across = S(settings.ignore_across):map(string.lower)
    ignore_players = S(settings.ignore_players) -- not active yet
    ignore_rare = true
    ignore_ex = true
    ignore_nostack = true
    
    player_only = true
    filter_by_player = true
	
    move_items = settings.move_items or false
end

bags = S{'safe','safe2','storage','locker','inventory','satchel','sack','case','wardrobe','wardrobe2','wardrobe3','wardrobe4','wardrobe5','wardrobe6','wardrobe7','wardrobe8'}

inv_str_to_id = {["inventory"] = 0, ["safe"] = 1, ["storage"] = 2, ["temp"] = 3, ["locker"] = 4, ["satchel"] = 5, ["sack"] = 6, ["case"] = 7, ["wardrobe"] = 8, ["safe2"] = 9, ["wardrobe2"] = 10, ["wardrobe3"] = 11, ["wardrobe4"] = 12, ["wardrobe5"] = 13, ["wardrobe6"] = 14, ["wardrobe7"] = 15, ["wardrobe8"] = 16, ["recycle"] = 17}
inv_id_to_str = {[0]="inventory", "safe", "storage", "temp", "locker", "satchel", "sack", "case", "wardrobe", "safe2", "wardrobe2", "wardrobe3", "wardrobe4", "wardrobe5", "wardrobe6", "wardrobe7", "wardrobe8", "recycle"}

-------------------------------------------------------------------------------------------------------------
preferences()

ignore_ids = res.items:filter(function(item) 
        return ignore_items:contains(item.name:lower()) or ignore_items:contains(item.name_log:lower()) 
    end):keyset()
ignore_across_ids = res.items:filter(function(item) 
        return ignore_across:contains(item.name:lower()) or ignore_across:contains(item.name_log:lower()) 
    end):keyset()
    
local get_flag = function(args, flag, default)
    for _, arg in ipairs(args) do
        if arg == flag then
            return false
        end
    end
    return default
end

function CanSendPol(id) return S(res.items[id].flags):contains('Can Send POL') end
function IsRare(id) return S(res.items[id].flags):contains('Rare') end
function IsExclusive(id) return S(res.items[id].flags):contains('Exclusive') or S(res.items[id].flags):contains('No PC Trade') end
function IsStackable(id) return res.items[id].stack > 1 end


function stack()
    windower.send_command('stack')  -- requires Itemizer on
end

function do_move()
    -- it should never happen, but let's be safe
    if table.length(to_move) == 0 then
        return
    end
    local bag, slot, count, iname = unpack(to_move[1])
    
    -- do stuff
    log("moving "..count.." "..iname.." to "..inv_id_to_str[bag])
    windower.ffxi.put_item(bag, slot, count)
    table.remove(to_move, 1)
    --log(bag, slot, count, iname)
    
    if table.length(to_move) > 0 then
        coroutine.schedule(do_move, 2)
    else
        coroutine.schedule(stack, 2)
    end
end

function find_item_in_bag(inv, id)
    slots = {}
    for _, item in ipairs(inv) do
        if item.id == id then
            slots[item.slot] = item.count
        end
    end
    return slots
end

function work(...)
    args = {...}    
    
    local ignore_rare = get_flag(args, 'rare', ignore_rare) -- where `settings` is the global settings table
    local ignore_ex = get_flag(args, 'ex', ignore_ex)
    local ignore_nostack = get_flag(args, 'nostack', ignore_nostack)
    local player_only = get_flag(args, 'findall', player_only)
    local filter_by_player = get_flag(args, 'nofilter', filter_by_player)
    
    local player = windower.ffxi.get_player().name
    
    local same_account = not player_only and function() 
        for _,v in pairs(settings.accounts) do 
            if v:contains(player) then 
                return S(v:gsub("%s+", ""):split(',')) --:ucfirst()
            end 
        end 
    end() or {}
    -- table.vprint(same_account)

    local inventory = windower.ffxi.get_items()
    local storages = {}
    
    storages[player] = {}
    
    local haystack = {}
    local results = 0

    -- flatten inventory
    --Shamelessly stolen from findAll. Many thanks to Zohno.    
    for bag,_ in pairs(bags:keyset()) do 
        storages[player][bag] = T{}
        for i = 1, inventory[bag].max do
            data = inventory[bag][i]
            if data.id ~= 0 then
                local id = data.id
                storages[player][bag][id] = (storages[player][bag][id] or 0) + data.count
            end
        end
    end
    
    -- get offline storages from findAll if available. This code is also lifted almost verbatim from findAll.
    if not player_only then
        local findall_data = windower.get_dir(windower.addon_path..'..\\findall\\data')
        if findall_data then
            for _,f in pairs(findall_data) do
                if f:sub(-4) == '.lua' and f:sub(1,-5) ~= player then
                    local success,result = pcall(dofile,windower.addon_path..'..\\findall\\data\\'..f)
                    if success then
                        storages[f:sub(1,-5)] = result
                    else
                        warning('Unable to retrieve updated item storage for %s.':format(f:sub(1,-5)))
                    end
                end
            end
        end
    end
    
    for character,inventory in pairs(storages) do
        if not ignore_players:contains(character) then
            for bag,items in pairs(inventory) do
                if bags:contains(bag) then
                    for id, count in pairs(items) do
                        id = tonumber(id)
                        --if item is valid, stackable, not ignored, not rare, not Exclusive
                        if res.items[id] 
                            and (not ignore_ids:contains(id))
                            and (IsStackable(id) or not ignore_nostack)
                            and (not IsRare(id) or not ignore_rare)
                            and (player_only or (character == player)
                                or not IsExclusive(id)
                                or (CanSendPol(id) and same_account[character])
                                or not ignore_ex)
                            and (player_only or not (character ~= player and ignore_across_ids:contains(id)))
                        then
                            --player str, bag str, id int, count int
                            location = (player_only and bag or character..': '..bag)
                            if not haystack[id] then haystack[id] = {} end
                            haystack[id][location] = count
                        end
                    end
                end
            end
        end
    end

    to_move = {}
    personal_inv = {}
    if move_items then
        personal_inv = windower.ffxi.get_items(inv_str_to_id["inventory"])
    end
    
    --print duplicates
    for id,locations in pairs(haystack) do
        if table.length(locations) > 1 then
            results = results +1
            log(res.items[id].name,'found in:')
            local extra_bags = {}
            local amt_to_move = 0
            local can_move = false
            for location,count in pairs(locations) do
                log('\t',location,count)
                if move_items then
                    if location == 'inventory' then
                        can_move = true
                        amt_to_move = count
                    else
                        extra_bags[#extra_bags+1] = location
                    end
                end
            end
            if can_move then
                -- find item in inventory
                slots_counts = find_item_in_bag(personal_inv, id)
                for slot, item_cnt in pairs(slots_counts) do
                    to_move[#to_move+1] = {inv_str_to_id[extra_bags[1]], slot, item_cnt, res.items[id].name}
                end
                can_move = false
            end
        end
    end
    
    if results >= 1 then
        log(results,'found.')
        if move_items and table.length(to_move) > 0 then
            do_move()
        end
    else
        log('No duplicates found. Congratulations!')
    end
    
    preferences()
end

function handle_commands(...)
    args = {...}
    
    local cmd = table.remove(args,1)
    
    if cmd == 'r' then -- shorthand for easy reloading
        windower.send_command('lua r '.._addon.name)
    elseif cmd == 'group' then
        local param = table.remove(args,1)
        if not param or param == 'display' then
            log('POL groupings:')
            table.vprint(settings.accounts)
            return
        elseif not tonumber(param) then
            log('Invalid parameter: '..param)
            return
        end
        local group = T(args):concat(','):gsub("%s+", ""):gsub(",,",",")
        settings.accounts[param] = group
        log('Added POL grouping %s: %s':format(param,group))
        config.save(settings,'all')
    else
        work(...)
    end
end

windower.register_event('addon command',handle_commands)
