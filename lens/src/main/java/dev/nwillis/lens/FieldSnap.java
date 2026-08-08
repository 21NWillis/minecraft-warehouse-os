package dev.nwillis.lens;

import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.world.level.block.state.BlockState;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.ClientTickEvent;

import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * The site inspection tool: a ONE-SHOT snapshot of a box centered on
 * wherever the operator is standing - completely separate from the
 * campus world model. Touches no config, no journal, no datum, no
 * baseMin/baseMax; the corp's own books stay closed while the Board
 * tours a neighboring facility.
 *
 * /fieldsnap [radius] [down] [up]   (defaults 48, 32, 16)
 *
 * Sweeps on the same per-tick budget as the world model, then writes
 * fieldsnap.json (same schema as snapshot.json, plus center/label) to
 * <instance>/paperclip_lens/. Unloaded chunks read as unknown - walk
 * the site while it sweeps for full coverage.
 */
public final class FieldSnap {
    private static boolean running;
    private static int minX, minY, minZ, sizeX, sizeY, sizeZ;
    private static long cursor, cells;
    private static int seen;
    private static List<String> entries;
    private static int lastPct = -1;

    public static String start(BlockPos center, int radius, int down, int up) {
        if (running) return "field snapshot already sweeping";
        minX = center.getX() - radius;
        minZ = center.getZ() - radius;
        minY = center.getY() - down;
        sizeX = radius * 2 + 1;
        sizeZ = radius * 2 + 1;
        sizeY = down + up + 1;
        cells = (long) sizeX * sizeY * sizeZ;
        cursor = 0;
        seen = 0;
        lastPct = -1;
        entries = new ArrayList<>();
        running = true;
        return "field snapshot sweeping " + sizeX + "x" + sizeY + "x" + sizeZ
            + " = " + cells + " cells (walk the site for coverage)";
    }

    public static void onClientTick(ClientTickEvent.Post event) {
        if (!running) return;
        Minecraft mc = Minecraft.getInstance();
        if (mc.level == null || mc.player == null) return;
        int budget = Math.max(1000, PaperclipLens.CONFIG.sweepBlocksPerTick);
        BlockPos.MutableBlockPos pos = new BlockPos.MutableBlockPos();
        for (int i = 0; i < budget && cursor < cells; i++, cursor++) {
            int y = (int) (cursor / ((long) sizeX * sizeZ));
            long rem = cursor % ((long) sizeX * sizeZ);
            int z = (int) (rem / sizeX);
            int x = (int) (rem % sizeX);
            pos.set(minX + x, minY + y, minZ + z);
            if (!mc.level.hasChunkAt(pos)) continue;
            seen++;
            BlockState state = mc.level.getBlockState(pos);
            if (state.isAir()) continue;
            String name = BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString();
            entries.add("[" + pos.getX() + "," + pos.getY() + "," + pos.getZ()
                + ",\"" + name + "\"]");
        }
        int pct = (int) (cursor * 100 / Math.max(1, cells));
        if (pct / 20 != lastPct / 20) {
            lastPct = pct;
            mc.player.displayClientMessage(
                Component.literal("field snapshot: " + pct + "%"), true);
        }
        if (cursor >= cells) {
            running = false;
            String msg = write();
            mc.player.displayClientMessage(Component.literal(msg), false);
        }
    }

    private static String write() {
        try {
            Path dir = FMLPaths.GAMEDIR.get().resolve("paperclip_lens");
            Files.createDirectories(dir);
            Path file = dir.resolve("fieldsnap.json");
            try (BufferedWriter w = Files.newBufferedWriter(file)) {
                w.write("{\"label\":\"fieldsnap\""
                    + ",\"generatedAt\":" + System.currentTimeMillis()
                    + ",\"min\":[" + minX + "," + minY + "," + minZ + "]"
                    + ",\"size\":[" + sizeX + "," + sizeY + "," + sizeZ + "]"
                    + ",\"known\":" + seen + ",\"cells\":" + cells
                    + ",\"blocks\":[");
                for (int i = 0; i < entries.size(); i++) {
                    if (i > 0) w.write(",");
                    w.write(entries.get(i));
                }
                w.write("]}");
            }
            long pct = seen * 100L / Math.max(1, cells);
            String out = "fieldsnap.json written: " + entries.size()
                + " blocks, " + pct + "% observed";
            entries = null;
            return out;
        } catch (IOException e) {
            entries = null;
            return "fieldsnap failed: " + e;
        }
    }
}
