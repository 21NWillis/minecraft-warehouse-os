package dev.nwillis.lens;

import net.minecraft.client.Minecraft;
import net.minecraft.client.player.LocalPlayer;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.item.ItemStack;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.ClientTickEvent;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Map;

/**
 * The up-channel for remote debugging: a status.json refreshed every
 * second with executor + player state, and append-only logs for every
 * placement attempt (placelog.jsonl) and remote command (cmdlog.jsonl).
 * The dev side reads these files directly - the operator never has to
 * relay symptoms by hand again.
 */
public final class Telemetry {
    private static long lastWrite;

    private static Path dir() {
        return FMLPaths.GAMEDIR.get().resolve("paperclip_lens");
    }

    public static void onClientTick(ClientTickEvent.Post event) {
        Minecraft mc = Minecraft.getInstance();
        if (mc.level == null || mc.player == null) return;
        if (mc.level.getGameTime() - lastWrite < 20) return;
        lastWrite = mc.level.getGameTime();
        LocalPlayer p = mc.player;
        ItemStack held = p.getInventory().getSelected();
        StringBuilder sb = new StringBuilder(512);
        sb.append("{\"t\":").append(System.currentTimeMillis())
            .append(",\"state\":\"").append(OrderExecutor.stateName())
            .append("\",\"order\":\"").append(OrderExecutor.orderName())
            .append("\",\"done\":").append(OrderExecutor.doneCount())
            .append(",\"total\":").append(OrderExecutor.totalCount())
            .append(",\"queued\":").append(OrderExecutor.queuedCount())
            .append(",\"deferred\":").append(OrderExecutor.deferredCount())
            .append(",\"passes\":").append(OrderExecutor.passCount())
            .append(",\"lastResult\":\"").append(OrderExecutor.lastClickResult())
            .append("\",\"results\":{");
        boolean first = true;
        for (Map.Entry<String, Integer> e : OrderExecutor.resultsTally().entrySet()) {
            if (!first) sb.append(",");
            first = false;
            sb.append("\"").append(e.getKey()).append("\":").append(e.getValue());
        }
        sb.append("},\"player\":{\"x\":").append(String.format("%.2f", p.getX()))
            .append(",\"y\":").append(String.format("%.2f", p.getY()))
            .append(",\"z\":").append(String.format("%.2f", p.getZ()))
            .append(",\"yaw\":").append(String.format("%.1f", p.getYRot()))
            .append(",\"pitch\":").append(String.format("%.1f", p.getXRot()))
            .append(",\"flying\":").append(p.getAbilities().flying)
            .append(",\"held\":\"")
            .append(held.isEmpty() ? "empty"
                : BuiltInRegistries.ITEM.getKey(held.getItem()).toString())
            .append("\",\"heldCount\":").append(held.getCount())
            .append("},\"dimension\":\"")
            .append(mc.level.dimension().location()).append("\"}");
        try {
            Files.createDirectories(dir());
            Files.writeString(dir().resolve("status.json"), sb.toString());
        } catch (IOException e) {
            PaperclipLens.LOG.warn("status write failed: {}", e.toString());
        }
    }

    private static void append(String file, String line) {
        try {
            Files.createDirectories(dir());
            Files.writeString(dir().resolve(file), line + "\n",
                StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        } catch (IOException e) {
            PaperclipLens.LOG.warn("{} append failed: {}", file, e.toString());
        }
    }

    public static void logPlace(BlockPos target, BlockPos support, Direction face,
            double eyeDist, String result, boolean placed, int attempt) {
        append("placelog.jsonl", "{\"t\":" + System.currentTimeMillis()
            + ",\"target\":[" + target.getX() + "," + target.getY() + "," + target.getZ()
            + "],\"support\":" + (support == null ? "null"
                : "[" + support.getX() + "," + support.getY() + "," + support.getZ() + "]")
            + ",\"face\":\"" + (face == null ? "none" : face.getName())
            + "\",\"eyeDist\":" + String.format("%.2f", eyeDist)
            + ",\"result\":\"" + result + "\",\"placed\":" + placed
            + ",\"attempt\":" + attempt + "}");
    }

    public static void logCmd(String cmd, String outcome) {
        append("cmdlog.jsonl", "{\"t\":" + System.currentTimeMillis()
            + ",\"cmd\":\"" + cmd + "\",\"outcome\":\"" + outcome.replace("\"", "'")
            + "\"}");
    }
}
