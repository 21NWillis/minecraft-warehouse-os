-- starlink: a tiny wireless mesh link-layer over rednet. Works on any modem
-- (wired for LAN, ender modem for cross-dimension / orbital). Provides node
-- presence, telemetry pub, and REAL round-trip latency measurement - so the
-- "Starlink ping: 3 ticks" readout is an actual number, not a bit.
local starlink = {}
starlink.__index = starlink

local PROTO = "starlink"

function starlink.new(node, role)
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then rednet.open(side) end
  end
  return setmetatable({
    node = node, role = role or "node",
    peers = {}, seq = 0, pending = {}, telem = {},
  }, starlink)
end

function starlink:setTelemetry(t)
  self.telem = t or {}
end

-- announce presence + current telemetry to the whole mesh
function starlink:beacon()
  rednet.broadcast({ type = "beacon", node = self.node, role = self.role,
                     telem = self.telem }, PROTO)
end

-- fire a latency probe at one peer (or all if target nil); result lands in
-- peers[name].rtt when the pong returns during pump()
function starlink:ping(target)
  local now = os.epoch("utc")
  -- drop probes that never got a pong (offline peer) so `pending` stays bounded
  for id, sentAt in pairs(self.pending) do
    if now - sentAt > 10000 then self.pending[id] = nil end
  end
  self.seq = self.seq + 1
  self.pending[self.seq] = now
  rednet.broadcast({ type = "ping", id = self.seq, from = self.node,
                     to = target }, PROTO)
end

-- service inbound traffic for up to `timeout` seconds
function starlink:pump(timeout)
  local deadline = os.epoch("utc") + (timeout or 0) * 1000
  repeat
    local remaining = (deadline - os.epoch("utc")) / 1000
    local sender, msg = rednet.receive(PROTO, math.max(0, remaining))
    if type(msg) == "table" then
      if msg.type == "beacon" and msg.node then
        local p = self.peers[msg.node] or {}
        p.role, p.telem, p.seen, p.id = msg.role, msg.telem, os.epoch("utc"), sender
        self.peers[msg.node] = p
      elseif msg.type == "ping" and (msg.to == nil or msg.to == self.node) then
        rednet.send(sender, { type = "pong", id = msg.id, from = self.node,
                              to = msg.from }, PROTO)
      elseif msg.type == "pong" and msg.to == self.node then
        local sentAt = self.pending[msg.id]
        if sentAt then
          local p = self.peers[msg.from] or {}
          p.rtt = os.epoch("utc") - sentAt
          p.seen = os.epoch("utc")
          self.peers[msg.from] = p
          self.pending[msg.id] = nil
        end
      end
    end
  until os.epoch("utc") >= deadline
end

-- forget peers unheard-from beyond staleSecs
function starlink:reap(staleSecs)
  local now = os.epoch("utc")
  for name, p in pairs(self.peers) do
    if (now - (p.seen or 0)) / 1000 > (staleSecs or 30) then
      self.peers[name] = nil
    end
  end
end

function starlink:list()
  local out = {}
  for name, p in pairs(self.peers) do
    out[#out + 1] = {
      node = name, role = p.role, rtt = p.rtt, telem = p.telem or {},
      age = (os.epoch("utc") - (p.seen or 0)) / 1000,
    }
  end
  table.sort(out, function(a, b) return a.node < b.node end)
  return out
end

return starlink
