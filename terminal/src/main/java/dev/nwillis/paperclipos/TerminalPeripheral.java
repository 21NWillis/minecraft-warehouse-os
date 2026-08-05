package dev.nwillis.paperclipos;

import com.google.gson.Gson;
import dan200.computercraft.api.lua.IArguments;
import dan200.computercraft.api.lua.LuaException;
import dan200.computercraft.api.lua.LuaFunction;
import dan200.computercraft.api.peripheral.IPeripheral;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * The CC face of the terminal. craftd wraps this, pushes catalog and
 * queue state in, and drains player orders out. All @LuaFunction
 * methods run on the server thread (mainThread = true), so BE access
 * needs no locking.
 */
public class TerminalPeripheral implements IPeripheral {
    private static final Gson GSON = new Gson();
    private final TerminalBlockEntity be;

    public TerminalPeripheral(TerminalBlockEntity be) {
        this.be = be;
    }

    @Override
    public String getType() {
        return "paperclip_terminal";
    }

    @Override
    public boolean equals(IPeripheral other) {
        return other instanceof TerminalPeripheral p && p.be == be;
    }

    /** Drain queued player orders: { {item=..., count=..., player=...}, ... } */
    @LuaFunction(mainThread = true)
    public final List<Map<String, Object>> getOrders() {
        List<Map<String, Object>> out = new ArrayList<>();
        for (TerminalBlockEntity.PendingOrder o : be.pendingOrders) {
            Map<String, Object> m = new HashMap<>();
            m.put("item", o.item());
            m.put("count", o.count());
            m.put("player", o.player());
            out.add(m);
        }
        be.pendingOrders.clear();
        return out;
    }

    /**
     * setCatalog(entries) - entries is a list of tables:
     * { id = "minecraft:iron_ingot", name = "Iron Ingot", stock = 1234 }
     */
    @LuaFunction(mainThread = true)
    public final void setCatalog(IArguments args) throws LuaException {
        be.catalogJson = GSON.toJson(sanitize(args.getTable(0)));
        be.push();
    }

    /** setQueue(lines) - list of tables { label = ..., status = ... } */
    @LuaFunction(mainThread = true)
    public final void setQueue(IArguments args) throws LuaException {
        be.queueJson = GSON.toJson(sanitize(args.getTable(0)));
        be.push();
    }

    /** toast(text, ok) - completion/failure notice shown in the GUI */
    @LuaFunction(mainThread = true)
    public final void toast(String text, boolean ok) {
        Map<String, Object> t = new HashMap<>();
        t.put("text", text);
        t.put("ok", ok);
        be.addToast(GSON.toJson(t));
    }

    // Lua tables arrive as Map<Object,Object> with numeric keys for the
    // array part; normalize to plain lists/maps so Gson emits clean JSON
    private static Object sanitize(Object value) {
        if (value instanceof Map<?, ?> map) {
            boolean array = !map.isEmpty();
            for (Object k : map.keySet()) {
                if (!(k instanceof Number)) {
                    array = false;
                    break;
                }
            }
            if (array) {
                List<Object> list = new ArrayList<>();
                for (int i = 1; map.containsKey((double) i); i++) {
                    list.add(sanitize(map.get((double) i)));
                }
                return list;
            }
            Map<String, Object> out = new HashMap<>();
            for (Map.Entry<?, ?> e : map.entrySet()) {
                out.put(String.valueOf(e.getKey()), sanitize(e.getValue()));
            }
            return out;
        }
        return value;
    }
}
