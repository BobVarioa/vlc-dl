lazily_loaded = false
JSON = nil

function lazy_load()
    if lazily_loaded then
        return nil
    end
    JSON = require "dkjson"
    lazily_loaded = true
end

function descriptor()
    return {
        title = "Youtube",
        capabilities = {"search"}
    }
end

local function dropnil(s)
    if s == nil then
        return ""
    else
        return s
    end
end

local function stringify(value)
    if type(value) == "table" then
        local temp = "{ "
        local i = 0
        for k, v in pairs(value) do
            if i == 0 then
                temp = temp .. stringify(k) .. " = " .. stringify(v)
            else
                temp = temp .. ", " .. stringify(k) .. " = " .. stringify(v)
            end
            i = i + 1
        end
        return temp .. " }"
    elseif type(value) == "nil" then
        return "nil"
    else
        return tostring(value)
    end
end

local function _get_format_url(format)
    -- prefer streaming formats
    if format.manifest_url then
        return format.manifest_url
    else
        return format.url
    end
end

local function ytdl(url, options)
    local opts = {
        raw = options.raw or false,
        args = options.args or "",
        deep = options.deep or false,
        eager = options.eager
    }
    local deepsearch = "--flat-playlist"
    if opts.deep then
        deepsearch = ""
    end
    -- checks if youtube-dl exists, else download the right file or update it

    local command = ""
    if opts.raw then
        command = "youtube-dl " .. opts.args .. " -j -i -c " .. deepsearch
    else
        command = "youtube-dl -j  -i  -c " .. deepsearch .. opts.args .. " \"" .. url .. "\""
    end

    local file = assert(io.popen(command, 'r')) -- run youtube-dl in json mode
    local tracks = {}
    while true do
        local output = file:read('*l') -- Read each license

        if not output then
            break
        end

        local json = JSON.decode(output) -- decode the json-output from youtube-dl

        if not json then
            break
        end

        local outurl = json.url
        local out_includes_audio = true
        local audiourl = nil
        if not outurl then
            if json.requested_formats then
                for key, format in pairs(json.requested_formats) do
                    if format.vcodec ~= (nil or "none") then
                        outurl = _get_format_url(format)
                        out_includes_audio = format.acodec ~= (nil or "none")
                    end

                    if format.acodec ~= (nil or "none") then
                        audiourl = _get_format_url(format)
                    end
                end
            else
                -- choose best
                for key, format in pairs(json.formats) do
                    outurl = _get_format_url(json.formats)
                end
                -- prefer audio and video
                for key, format in pairs(json.formats) do
                    if format.vcodec ~= (nil or "none") and format.acodec ~= (nil or "none") then
                        outurl = _get_format_url(format)
                    end
                end
            end
        end

        if outurl then
            if (json._type == "url" or json._type == "url_transparent") and json.ie_key == "Youtube" then
                outurl = "https://www.youtube.com/watch?v=" .. outurl
            end

            local category = nil
            if json.categories then
                category = json.categories[1]
            end

            local year = nil
            if json.release_year then
                year = json.release_year
            elseif json.release_date then
                year = string.sub(json.release_date, 1, 4)
            elseif json.upload_date then
                year = string.sub(json.upload_date, 1, 4)
            end

            local thumbnail = nil
            if json.thumbnails then
                thumbnail = json.thumbnails[#json.thumbnails].url
            end

            jsoncopy = {}
            for k in pairs(json) do
                jsoncopy[k] = tostring(json[k])
            end

            json = jsoncopy

            local item = {
                path = outurl,
                name = json.title,
                duration = json.duration,

                -- for a list of these check vlc/modules/lua/libs/sd.c
                title = json.track or json.title,
                artist = json.artist or json.creator or json.uploader or json.playlist_uploader,
                genre = json.genre or category,
                copyright = json.license,
                album = json.album or json.playlist_title or json.playlist,
                tracknum = json.track_number or json.playlist_index,
                description = json.description,
                rating = json.average_rating,
                date = year,
                -- setting
                url = json.webpage_url or url,
                -- language
                -- nowplaying
                -- publisher
                -- encodedby
                arturl = json.thumbnail or thumbnail,
                trackid = json.track_id or json.episode_id or json.id,
                tracktotal = json.n_entries,
                -- director
                season = json.season or json.season_number or json.season_id,
                episode = json.episode or json.episode_number,
                show_name = json.series,
                -- actors

                meta = json,
                options = {}
            }

            if not out_includes_audio and audiourl and outurl ~= audiourl then
                item['options'][':input-slave'] = ":input-slave=" .. audiourl;
            end

            if type(opts.eager) == "function" then
                opts.eager(item)
            else
                table.insert(tracks, item)
            end
        end
    end
    file:close()
    return tracks
end

local function parse_channel(channel_name)
    local file = assert(io.popen("youtube-dl -j  -i -c \"ytsearch:" .. channel_name .. "\"", 'r')) -- run youtube-dl in json mode
    local output = file:read('*l') -- Read each line
    local json = JSON.decode(output) -- decode the json-output from youtube-dl

    if string.lower(json.channel) == string.lower(channel_name) then
        return json.channel_id
    end

    file:close()
    return nil
end

local function unpack(table, i)
    i = i or 1
    if i > #table then
        return
    end

    return table[i], unpack(table, i + 1)
end

local function async(func)
    return coroutine.resume(coroutine.create(function()
        func()
    end))
    -- return func()
end

local function add_feed(url)
    return async(function ()
        local title = string.gsub(url, ".*/(.-)$", function(str)
            return string.upper(string.sub(str, 0, 1)) .. string.sub(str, 2, -1) -- Make the first letter uppercase
        end)
        local node = vlc.sd.add_node({
            title = title
        })
        vlc.msg.dbg("Creating Feed: " .. title)
        ytdl(url, {
            deep = true,
            eager = function(item)
                node:add_subitem(item)
                vlc.msg.dbg("Loaded video: " .. item.title)
            end
        })
    end)
end



local function escape(blah)
    return vlc.strings.convert_xml_special_chars(blah)
end

local search_node = nil

function main()
    lazy_load()

    search_node = vlc.sd.add_node({
        title = "Search Results "
    })
    add_feed("https://youtube.com/feed/recommended")

    if true then
        add_feed("https://www.youtube.com/feed/subscriptions")
    end
end
--[[
Format:

$ --youtube-dl-args "make sure to put a url"
#15 @ChannelName query 
: 15 results from channel name matching query

--]]

local last_query = ""
function search(query)
    lazy_load()
    if last_query == query then
        return
    end
    last_query = query

    if search_node then
        vlc.sd.remove_node(search_node)
        search_node = vlc.sd.add_node({
            title = "Search Results"
        })
    end

    local args = string.match(query, "^%$%s*(.*)") -- if the string starts with $
    if args then
        ytdl("", {
            deep = true,
            raw = true,
            args = args,
            eager = function(item)
                search_node:add_subitem(item)
            end
        })
    else
        local number = string.match(query, "#(%d*)") or "5"
        local channel = string.match(query, "@([^%s]*)")
        local rest = string.gsub(string.gsub(query, "(#%d*)%s?", "", 1), "(@[^%s]*)%s?", "", 1)

        if channel then
            local channel_id = parse_channel(channel)
            if channel_id then
                ytdl("https://www.youtube.com/channel/" .. escape(channel_id), {
                    deep = true,
                    args = "--max-downloads=" .. number,
                    eager = function(item)
                        search_node:add_subitem(item)
                    end
                })
            end
        else
            ytdl("ytsearch" .. number .. ":" .. rest, {
                deep = true,
                eager = function(item)
                    search_node:add_subitem(item)
                end
            })
        end
    end
end
