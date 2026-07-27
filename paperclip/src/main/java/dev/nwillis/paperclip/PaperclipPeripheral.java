package dev.nwillis.paperclip;

import dan200.computercraft.api.lua.LuaException;
import dan200.computercraft.api.lua.LuaFunction;
import dan200.computercraft.api.peripheral.IPeripheral;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.item.ItemStack;

import javax.annotation.Nullable;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

/**
 * The "paperclip" peripheral. Three API groups:
 * - delivery/chat: give(player), notify(player, msg), broadcast(msg), players()
 * - server health: mspt(), tps()
 * - cluster primitives (shared across ALL terminals): get/set/del/incr/cas,
 *   push/pop/qsize
 * Deliberately conservative: it moves items that physically exist and reports
 * observable facts. No item creation, no player inventory reads, no teleports.
 */
public final class PaperclipPeripheral implements IPeripheral {
    private static final long MESSAGE_COOLDOWN_MS = 1000;

    private final PaperclipTerminalBlockEntity terminal;
    private long lastMessageAt = 0;

    PaperclipPeripheral(PaperclipTerminalBlockEntity terminal) {
        this.terminal = terminal;
    }

    @Override
    public String getType() {
        return "paperclip";
    }

    @Override
    public boolean equals(@Nullable IPeripheral other) {
        return this == other
            || (other instanceof PaperclipPeripheral p && p.terminal == terminal);
    }

    private MinecraftServer server() throws LuaException {
        var level = terminal.getLevel();
        if (level == null || level.getServer() == null) {
            throw new LuaException("terminal is not loaded");
        }
        return level.getServer();
    }

    private ClusterState cluster() throws LuaException {
        return ClusterState.get(server());
    }

    private ServerPlayer onlinePlayer(String name) throws LuaException {
        ServerPlayer player = server().getPlayerList().getPlayerByName(name);
        if (player == null) throw new LuaException("player not online: " + name);
        return player;
    }

    private boolean rateLimited() {
        long now = System.currentTimeMillis();
        if (now - lastMessageAt < MESSAGE_COOLDOWN_MS) return true;
        lastMessageAt = now;
        return false;
    }

    // ------------------------------------------------------------ delivery

    @LuaFunction(mainThread = true)
    public final Map<Integer, String> players() throws LuaException {
        Map<Integer, String> out = new HashMap<>();
        int i = 1;
        for (ServerPlayer p : server().getPlayerList().getPlayers()) {
            out.put(i++, p.getGameProfile().getName());
        }
        return out;
    }

    /**
     * Moves the terminal's inventory into the named player's inventory.
     * Returns the number of items transferred; whatever doesn't fit stays
     * in the terminal.
     */
    @LuaFunction(mainThread = true)
    public final int give(String playerName) throws LuaException {
        ServerPlayer target = onlinePlayer(playerName);
        var items = terminal.getItemHandler();
        int moved = 0;
        for (int slot = 0; slot < items.getSlots(); slot++) {
            ItemStack stack = items.extractItem(slot, 64, false);
            if (stack.isEmpty()) continue;
            int before = stack.getCount();
            target.getInventory().add(stack);
            moved += before - stack.getCount();
            if (!stack.isEmpty()) {
                items.insertItem(slot, stack, false);
            }
        }
        return moved;
    }

    @LuaFunction(mainThread = true)
    public final boolean notify(String playerName, String message) throws LuaException {
        if (rateLimited()) return false;
        onlinePlayer(playerName).sendSystemMessage(
            Component.literal("[paperclip] " + message));
        return true;
    }

    @LuaFunction(mainThread = true)
    public final boolean broadcast(String message) throws LuaException {
        if (rateLimited()) return false;
        server().getPlayerList().broadcastSystemMessage(
            Component.literal("[paperclip] " + message), false);
        return true;
    }

    // ------------------------------------------------------- server health

    @LuaFunction(mainThread = true)
    public final double mspt() throws LuaException {
        return server().getAverageTickTimeNanos() / 1.0e6;
    }

    @LuaFunction(mainThread = true)
    public final double tps() throws LuaException {
        double ms = mspt();
        return ms <= 0 ? 20.0 : Math.min(20.0, 1000.0 / ms);
    }

    // -------------------------------------------------- cluster primitives

    @LuaFunction(mainThread = true)
    public final Object get(String key) throws LuaException {
        return cluster().kvGet(key);
    }

    @LuaFunction(mainThread = true)
    public final boolean set(String key, String value) throws LuaException {
        return cluster().kvSet(key, value);
    }

    @LuaFunction(mainThread = true)
    public final void del(String key) throws LuaException {
        cluster().kvDelete(key);
    }

    /** Atomic increment; returns the new value. Default delta is 1. */
    @LuaFunction(mainThread = true)
    public final long incr(String key, Optional<Long> delta) throws LuaException {
        return cluster().kvIncrement(key, delta.orElse(1L));
    }

    /**
     * Atomic compare-and-swap. Pass nil as expected to mean "set only if
     * the key does not exist" (a lock acquire). Returns success.
     */
    @LuaFunction(mainThread = true)
    public final boolean cas(String key, Optional<String> expected, String value) throws LuaException {
        return cluster().kvCompareAndSwap(key, expected.orElse(null), value);
    }

    @LuaFunction(mainThread = true)
    public final boolean push(String queue, String value) throws LuaException {
        return cluster().queuePush(queue, value);
    }

    /** Pops the oldest entry from the queue, or nil if it is empty. */
    @LuaFunction(mainThread = true)
    public final Object pop(String queue) throws LuaException {
        return cluster().queuePop(queue);
    }

    @LuaFunction(mainThread = true)
    public final int qsize(String queue) throws LuaException {
        return cluster().queueSize(queue);
    }
}
