package dev.nwillis.lens;

import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterKeyMappingsEvent;
import org.lwjgl.glfw.GLFW;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.HashMap;
import java.util.Map;

/**
 * The client-side world model: Claude's eyes. Sweeps the configured base
 * bounds a few thousand blocks per tick, diffing against a last-known
 * model. Every observed change appends to journal.jsonl (the base's
 * commit log); F10 dumps the whole model to snapshot.json (the base's
 * checkout). Both land in <instance>/paperclip_lens/ where the dev-side
 * tooling reads them directly - no pastebin, no tokens, no turtles.
 *
 * Honest scope: the client only sees loaded chunks in its own dimension,
 * so the journal is an OPPORTUNISTIC record (great while you play, blind
 * while you don't) and the model holds last-known state. Periodic turtle
 * surveys remain the reconciliation tool for anywhere you aren't.
 */
public final class WorldModel {
    private static final int AIR = 0;

    private static KeyMapping snapshotKey;
    private static final Map<String, Integer> paletteIds = new HashMap<>();
    private static final Map<Integer, String> paletteNames = new HashMap<>();
    private static final Map<Long, Integer> model = new HashMap<>();
    private static long cursor;
    private static long cells = 1;
    private static boolean boundsOk;
    private static int minX, minY, minZ, sizeX, sizeY, sizeZ;
    private static BufferedWriter journal;
    private static long lastFlush;

    public static void registerKeys(RegisterKeyMappingsEvent event) {
        snapshotKey = new KeyMapping("key.paperclip_lens.snapshot", GLFW.GLFW_KEY_F10,
            "key.categories.paperclip_lens");
        event.register(snapshotKey);
        arm();
    }

    /**
     * (Re)build sweep state from the configured corners. Called at startup
     * and again by /bottomleft + /topright, so bounds set in game take
     * effect immediately. Changing bounds resets the model - the journal
     * file survives, the in-memory diff base starts over.
     */
    public static String arm() {
        int[] min = PaperclipLens.CONFIG.baseMin;
        int[] max = PaperclipLens.CONFIG.baseMax;
        boundsOk = min != null && max != null && min.length == 3 && max.length == 3;
        if (!boundsOk) {
            PaperclipLens.LOG.info(
                "world model idle: set both corners (/bottomleft, /topright)");
            return "world model idle: set the other corner";
        }
        model.clear();
        paletteIds.clear();
        paletteNames.clear();
        cursor = 0;
        minX = Math.min(min[0], max[0]);
        minY = Math.min(min[1], max[1]);
        minZ = Math.min(min[2], max[2]);
        sizeX = Math.abs(max[0] - min[0]) + 1;
        sizeY = Math.abs(max[1] - min[1]) + 1;
        sizeZ = Math.abs(max[2] - min[2]) + 1;
        cells = (long) sizeX * sizeY * sizeZ;
        paletteIds.put("minecraft:air", AIR);
        paletteNames.put(AIR, "minecraft:air");
        String status = "world model armed: " + sizeX + "x" + sizeY + "x" + sizeZ
            + " = " + cells + " cells";
        PaperclipLens.LOG.info(status);
        return status;
    }

    private static Path dir() {
        return FMLPaths.GAMEDIR.get().resolve("paperclip_lens");
    }

    private static int idFor(String name) {
        Integer id = paletteIds.get(name);
        if (id == null) {
            id = paletteIds.size();
            paletteIds.put(name, id);
            paletteNames.put(id, name);
        }
        return id;
    }

    private static void journalLine(int x, int y, int z, String block) {
        try {
            if (journal == null) {
                Files.createDirectories(dir());
                journal = Files.newBufferedWriter(dir().resolve("journal.jsonl"),
                    StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            }
            journal.write("{\"t\":" + System.currentTimeMillis()
                + ",\"x\":" + x + ",\"y\":" + y + ",\"z\":" + z
                + ",\"b\":\"" + block + "\"}\n");
        } catch (IOException e) {
            PaperclipLens.LOG.warn("journal write failed: {}", e.toString());
        }
    }

    public static void onClientTick(ClientTickEvent.Post event) {
        Minecraft mc = Minecraft.getInstance();
        while (snapshotKey != null && snapshotKey.consumeClick()) {
            String msg = snapshot();
            if (mc.player != null) {
                mc.player.displayClientMessage(Component.literal(msg), true);
            }
        }
        if (!boundsOk || mc.level == null || mc.player == null) return;
        String dim = mc.level.dimension().location().toString();
        if (!dim.equals(PaperclipLens.CONFIG.modelDimension)) return;

        int budget = Math.max(1000, PaperclipLens.CONFIG.sweepBlocksPerTick);
        BlockPos.MutableBlockPos pos = new BlockPos.MutableBlockPos();
        for (int i = 0; i < budget; i++) {
            long c = cursor;
            cursor = (cursor + 1) % cells;
            int y = (int) (c / ((long) sizeX * sizeZ));
            long rem = c % ((long) sizeX * sizeZ);
            int z = (int) (rem / sizeX);
            int x = (int) (rem % sizeX);
            pos.set(minX + x, minY + y, minZ + z);
            if (!mc.level.hasChunkAt(pos)) continue;   // unseen: keep last-known
            BlockState state = mc.level.getBlockState(pos);
            ResourceLocation key = BuiltInRegistries.BLOCK.getKey(state.getBlock());
            String name = state.isAir() ? "minecraft:air" : key.toString();
            int id = idFor(name);
            Integer prev = model.put(c, id);
            if (prev != null && prev != id) {
                journalLine(pos.getX(), pos.getY(), pos.getZ(), name);
            }
        }
        if (journal != null && mc.level.getGameTime() - lastFlush > 100) {
            lastFlush = mc.level.getGameTime();
            try {
                journal.flush();
            } catch (IOException ignored) {
            }
        }
    }

    /** Dump last-known model to snapshot.json; returns a status line. */
    public static String snapshot() {
        if (!boundsOk) return "world model unconfigured (baseMin/baseMax)";
        try {
            Files.createDirectories(dir());
            Path file = dir().resolve("snapshot.json");
            try (BufferedWriter w = Files.newBufferedWriter(file)) {
                w.write("{\"generatedAt\":" + System.currentTimeMillis()
                    + ",\"min\":[" + minX + "," + minY + "," + minZ + "]"
                    + ",\"size\":[" + sizeX + "," + sizeY + "," + sizeZ + "]"
                    + ",\"known\":" + model.size() + ",\"cells\":" + cells
                    + ",\"blocks\":[");
                boolean first = true;
                for (Map.Entry<Long, Integer> e : model.entrySet()) {
                    if (e.getValue() == AIR) continue;
                    long c = e.getKey();
                    int y = (int) (c / ((long) sizeX * sizeZ));
                    long rem = c % ((long) sizeX * sizeZ);
                    int z = (int) (rem / sizeX);
                    int x = (int) (rem % sizeX);
                    if (!first) w.write(",");
                    first = false;
                    w.write("[" + (minX + x) + "," + (minY + y) + "," + (minZ + z)
                        + ",\"" + paletteNames.get(e.getValue()) + "\"]");
                }
                w.write("]}");
            }
            long pct = model.size() * 100L / Math.max(1, cells);
            return "snapshot written (" + pct + "% of base observed)";
        } catch (IOException e) {
            return "snapshot failed: " + e;
        }
    }
}
