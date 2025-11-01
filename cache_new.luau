--!strict

type Metadata = {
    timestamp: number,
	ttl: number,
	last_access: number
}

type Stats = {
    size: number,
    max_size: number,
    keys: { string }
}

local MAX_CACHE_SIZE: number = 10000 -- max cached keys
local DEFAULT_TTL: number = 300 -- ttl in secs

local access_order: { string } = {}
local cache: { [string]: any } = {}
local cache_metadata: { [string]: Metadata } = {}
local threads: { thread } = {}

local function get_size(): number
    return #access_order
end

local function delete(key: string)
    cache[key] = nil
    cache_metadata[key] = nil
    table.remove(access_order, table.find(access_order, key))
end

local function evit_lru()
    if #access_order > 0 then
        delete(access_order[1])
    end
end

local function set_metadata(key: string, ttl: number?)
    local _time = os.time()
    cache_metadata[key] = table.freeze({
        timestamp = _time,
        ttl = ttl or DEFAULT_TTL,
        last_access = _time
    })
end

local function update_access_order(key: string)
    table.remove(access_order, table.find(access_order, key))
    table.insert(access_order, key)
end

local function set<T>(key: string, val: T, ttl: number?)
    if not cache[key] and get_size() >= MAX_CACHE_SIZE then
        evit_lru()
    end

    cache[key] = val
    set_metadata(key, ttl)
    update_access_order(key)
end

local function is_expired(key: string): boolean
    local metadata = cache_metadata[key]

    if metadata then
        return os.time() - metadata.timestamp > metadata.ttl
    end

    return false
end

local function get<T>(key: string): T?
    local metadata = cache_metadata[key]

    if not metadata then
        return
    end

    if is_expired(key) then
        delete(key)
        return
    end

    set_metadata(key, metadata.ttl)
    update_access_order(key)

    return cache[key]
end

local function exists(key: string): boolean
    if not cache[key] then
        return false
    end

    if is_expired(key) then
        delete(key)
        return false
    end

    return true
end

local function expire(key: string, ttl: number?)
    if cache_metadata[key] then
        set_metadata(key, ttl)
    end
end

local function ttl(key: string): number
    local metadata = cache_metadata[key]

    if not metadata then
        return -2
    end

    local remaining = metadata.ttl - (os.time() - metadata.timestamp)
    return if remaining > 0 then remaining else -2
end

local function keys(pattern: string): { string }
    local _keys = {}

    pattern = string.gsub(string.gsub(pattern, "%*", ".*"), "%?", ".")

    for key in cache do
        if not is_expired(key) and string.match(key, pattern) then
            table.insert(_keys, key)
        end
    end

    return table.freeze(_keys)
end

local function flush_all()
    cache = {}
    cache_metadata = {}
    table.clear(access_order)
end

local function get_stats(): Stats
    return table.freeze({
        size = get_size(),
        max_size = MAX_CACHE_SIZE,
        keys = keys(".*")
    })
end

return {}
