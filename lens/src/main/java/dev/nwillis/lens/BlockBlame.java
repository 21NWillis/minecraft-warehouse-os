package dev.nwillis.lens;

import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.world.phys.BlockHitResult;
import net.minecraft.world.phys.HitResult;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.ClientTickEvent;
import net.neoforged.neoforge.client.event.RegisterKeyMappingsEvent;
import org.lwjgl.glfw.GLFW;

import java.io.BufferedReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/**
 * git blame, but for the world. The operator called the change journal
 * "a git system for the base" - so here is the command every repo
 * earns: look at a block, press F7, and Lens replays that position's
 * history from journal.jsonl. "Who put this here and when" becomes a
 * keypress instead of an argument.
 */
public final class BlockBlame {
    private static KeyMapping blameKey;
    private static final SimpleDateFormat FMT = new SimpleDateFormat("MMM d HH:mm");

    public static void registerKeys(RegisterKeyMappingsEvent event) {
        blameKey = new KeyMapping("key.paperclip_lens.blame", GLFW.GLFW_KEY_F7,
            "key.categories.paperclip_lens");
        event.register(blameKey);
    }

    public static void onClientTick(ClientTickEvent.Post event) {
        Minecraft mc = Minecraft.getInstance();
        while (blameKey != null && blameKey.consumeClick()) {
            if (mc.player == null || mc.level == null) continue;
            if (!(mc.hitResult instanceof BlockHitResult hit)
                || mc.hitResult.getType() != HitResult.Type.BLOCK) {
                mc.player.displayClientMessage(
                    Component.literal("§d[blame]§r look at a block first"), true);
                continue;
            }
            blame(hit.getBlockPos());
        }
    }

    private static void blame(BlockPos pos) {
        Minecraft mc = Minecraft.getInstance();
        Path journal = FMLPaths.GAMEDIR.get()
            .resolve("paperclip_lens").resolve("journal.jsonl");
        String needle = "\"x\":" + pos.getX() + ",\"y\":" + pos.getY()
            + ",\"z\":" + pos.getZ() + ",";
        List<String> history = new ArrayList<>();
        if (Files.exists(journal)) {
            try (BufferedReader r = Files.newBufferedReader(journal)) {
                String line;
                while ((line = r.readLine()) != null) {
                    if (line.contains(needle)) history.add(line);
                }
            } catch (Exception e) {
                PaperclipLens.LOG.warn("blame read failed: {}", e.toString());
            }
        }
        String now = mc.level.getBlockState(pos).getBlock().toString();
        mc.player.displayClientMessage(Component.literal(
            "§d── blame " + pos.toShortString() + " ── now " + now), false);
        if (history.isEmpty()) {
            mc.player.displayClientMessage(Component.literal(
                "§7no recorded changes (predates the journal, or unobserved)"), false);
            return;
        }
        int from = Math.max(0, history.size() - 5);
        if (from > 0) {
            mc.player.displayClientMessage(Component.literal(
                "§7… " + from + " earlier change(s)"), false);
        }
        for (int i = from; i < history.size(); i++) {
            String line = history.get(i);
            long t = extractLong(line);
            String block = extractBlock(line);
            mc.player.displayClientMessage(Component.literal(
                "§7" + FMT.format(new Date(t)) + " §f→ " + block), false);
        }
    }

    private static long extractLong(String line) {
        int i = line.indexOf("\"t\":");
        if (i < 0) return 0;
        int j = line.indexOf(',', i);
        try {
            return Long.parseLong(line.substring(i + 4, j));
        } catch (Exception e) {
            return 0;
        }
    }

    private static String extractBlock(String line) {
        int i = line.indexOf("\"b\":\"");
        if (i < 0) return "?";
        int j = line.indexOf('"', i + 5);
        return j < 0 ? "?" : line.substring(i + 5, j);
    }
}
