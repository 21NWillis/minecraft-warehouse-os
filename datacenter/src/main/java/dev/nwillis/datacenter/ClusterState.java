package dev.nwillis.datacenter;

import net.minecraft.core.HolderLookup;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.ListTag;
import net.minecraft.nbt.StringTag;
import net.minecraft.nbt.Tag;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.level.saveddata.SavedData;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.Map;

/**
 * Server-wide shared state for all Datacenter Terminals: a persistent
 * key-value store with atomic operations, plus named FIFO work queues.
 * Every terminal on the server sees the same state, which is what lets
 * independent computers behave like one distributed system.
 */
public final class ClusterState extends SavedData {
    private static final String NAME = "datacenter_cluster";
    static final int MAX_KEYS = 4096;
    static final int MAX_VALUE_LENGTH = 16 * 1024;
    static final int MAX_QUEUE_LENGTH = 4096;

    private final Map<String, String> store = new HashMap<>();
    private final Map<String, Deque<String>> queues = new HashMap<>();

    public static ClusterState get(MinecraftServer server) {
        return server.overworld().getDataStorage().computeIfAbsent(
            new SavedData.Factory<>(ClusterState::new, ClusterState::load), NAME);
    }

    private static ClusterState load(CompoundTag tag, HolderLookup.Provider registries) {
        ClusterState state = new ClusterState();
        CompoundTag kv = tag.getCompound("kv");
        for (String key : kv.getAllKeys()) {
            state.store.put(key, kv.getString(key));
        }
        CompoundTag qs = tag.getCompound("queues");
        for (String name : qs.getAllKeys()) {
            Deque<String> queue = new ArrayDeque<>();
            for (Tag item : qs.getList(name, Tag.TAG_STRING)) {
                queue.addLast(item.getAsString());
            }
            state.queues.put(name, queue);
        }
        return state;
    }

    @Override
    public CompoundTag save(CompoundTag tag, HolderLookup.Provider registries) {
        CompoundTag kv = new CompoundTag();
        store.forEach(kv::putString);
        tag.put("kv", kv);
        CompoundTag qs = new CompoundTag();
        queues.forEach((name, queue) -> {
            ListTag list = new ListTag();
            queue.forEach(value -> list.add(StringTag.valueOf(value)));
            qs.put(name, list);
        });
        tag.put("queues", qs);
        return tag;
    }

    public String kvGet(String key) {
        return store.get(key);
    }

    public boolean kvSet(String key, String value) {
        if (value.length() > MAX_VALUE_LENGTH) return false;
        if (!store.containsKey(key) && store.size() >= MAX_KEYS) return false;
        store.put(key, value);
        setDirty();
        return true;
    }

    public void kvDelete(String key) {
        if (store.remove(key) != null) setDirty();
    }

    public long kvIncrement(String key, long delta) {
        long current;
        try {
            current = Long.parseLong(store.getOrDefault(key, "0"));
        } catch (NumberFormatException e) {
            current = 0;
        }
        long next = current + delta;
        store.put(key, Long.toString(next));
        setDirty();
        return next;
    }

    /** Atomic compare-and-swap; expected == null means "only set if absent". */
    public boolean kvCompareAndSwap(String key, String expected, String value) {
        String current = store.get(key);
        boolean matches = (expected == null) ? current == null : expected.equals(current);
        if (!matches) return false;
        return kvSet(key, value);
    }

    public boolean queuePush(String name, String value) {
        if (value.length() > MAX_VALUE_LENGTH) return false;
        Deque<String> queue = queues.computeIfAbsent(name, k -> new ArrayDeque<>());
        if (queue.size() >= MAX_QUEUE_LENGTH) return false;
        queue.addLast(value);
        setDirty();
        return true;
    }

    public String queuePop(String name) {
        Deque<String> queue = queues.get(name);
        if (queue == null || queue.isEmpty()) return null;
        setDirty();
        return queue.pollFirst();
    }

    public int queueSize(String name) {
        Deque<String> queue = queues.get(name);
        return queue == null ? 0 : queue.size();
    }
}
