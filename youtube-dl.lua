JSON = require "dkjson" -- load additional json routines

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
        --[[
    elseif type(value) == "string" then
        return "\"" .. value .. "\""
    --]]
    elseif type(value) == "nil" then
        return "nil"
    else
        return tostring(value)
    end
end

local function get_format_url(format)
    -- prefer streaming formats
    if format.manifest_url then
        return format.manifest_url
    else
        return format.url
    end
end

local function log(...)
    local built = ""
    for i, v in ipairs({...}) do
        built = built .. stringify(v)
    end
    vlc.msg.dbg("[YT-DL] " .. built)
end

-- Probe function.
function probe()
    return (vlc.access == "http" or vlc.access == "https") and (string.lower(vlc.peek(9)) == "<!doctype")
end

-- Parse function.
function parse()
    local url = vlc.access .. "://" .. vlc.path -- get full url
    
    local file = nil
    local status, err = pcall(function()
        log("Loading url: ", url)
        -- run youtube-dl in json mode
        file = assert(io.popen("youtube-dl -j --flat-playlist -i  -c --mark-watched \"" .. url .. "\"", 'r'))
        log("Completed loading url: ", url)
    end)
    if file ~= nil and status then
        local tracks = {}
        log("Parsing data...")
        local i = 1
        while true do
            local output = file:read('*l') -- Read each line

            if not output then
                break
            else
                log("Parsing line ", i)
            end

            local json = JSON.decode(output) -- decode the json-output from youtube-dl

            if not json then
                log("JSON decode failed")
                break
            end

            local outurl = json.url
            local out_includes_audio = true
            local audiourl = nil
            if not outurl then
                if json.requested_formats then
                    for key, format in pairs(json.requested_formats) do
                        local acodec = format.acodec ~= nil and format.acodec ~= "none"
                        local vcodec = format.vcodec ~= nil and format.vcodec ~= "none"

                        if vcodec then
                            outurl = get_format_url(format)
                            out_includes_audio = acodec
                        end

                        if acodec then
                            audiourl = get_format_url(format)
                        end
                    end
                else
                    -- choose best
                    for key, format in pairs(json.formats) do
                        outurl = get_format_url(format)
                    end
                    -- prefer audio and video
                    for key, format in pairs(json.formats) do
                        local acodec = format.acodec ~= nil and format.acodec ~= "none"
                        local vcodec = format.vcodec ~= nil and format.vcodec ~= "none"
                        if vcodec and acodec then
                            outurl = get_format_url(format)
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

                local thumbnail = json.thumbnail
                if thumbnail == nil and json.thumbnails then
                    thumbnail = json.thumbnails[#json.thumbnails].url
                end

                local chapters = nil
                if json.chapters then
                    local chaps = {}
                    for i, v in ipairs(json.chapters) do
                        table.insert(chaps, string.format("{name=%s,time=%s}", v.title, v.start_time))
                    end
                    chapters = string.format(':bookmarks="%s"', table.concat(chaps, ","))
                end

                local stringy = {}
                json = setmetatable(json, { -- lazy tostring
                    __index = function(t, k)
                        local cached = stringy[k]
                        if cached then
                            return cached
                        else
                            local val = rawget(t, k)
                            if val == nil then
                                return val
                            else
                                stringy[k] = val
                                return tostring(val)
                            end
                        end
                    end
                })

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
                    encodedby = "Youtube-DL " .. tostring(json.extractor_key or json.extractor),
                    arturl = thumbnail,
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
                    table.insert(item.options, ":input-slave=" .. audiourl)
                end
                if chapters then
                    table.insert(item.options, chapters)
                end

                table.insert(tracks, item)
            end
            i = i + 1
        end
        file:close()
        log("Parsing complete")
        return tracks
    else
        -- Failsafe if the user closes the window
        log("Download failed, leaving url as it is")
        return {{
            path = url
        }}
    end
end