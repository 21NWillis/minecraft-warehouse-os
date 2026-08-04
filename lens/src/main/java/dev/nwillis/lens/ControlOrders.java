package dev.nwillis.lens;

import net.minecraft.client.Minecraft;
import net.minecraft.network.chat.Component;
import net.neoforged.fml.loading.FMLPaths;
import net.neoforged.neoforge.client.event.ClientTickEvent;

import java.io.IOException;
import java.nio.file.DirectoryStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;

/**
 * Claude-control scaffold (v2.0: perception + acknowledgement only).
 * Watches <instance>/paperclip_lens/orders/ for *.json build orders
 * dropped by the dev-side tooling, announces them to the player, and
 * files them under orders/seen/. The actual player-actuation executor
 * (the "hijack me" the operator explicitly requested) ships as v2.1
 * behind an opt-in toggle - this scaffold proves the channel and lets
 * the order format stabilize first. No world mutation here.
 */
public final class ControlOrders {
    private static long lastPoll;

    private static Path ordersDir() {
        return FMLPaths.GAMEDIR.get().resolve("paperclip_lens").resolve("orders");
    }

    public static void onClientTick(ClientTickEvent.Post event) {
        Minecraft mc = Minecraft.getInstance();
        if (mc.level == null || mc.player == null) return;
        if (mc.level.getGameTime() - lastPoll < 100) return;   // 5s poll
        lastPoll = mc.level.getGameTime();

        Path dir = ordersDir();
        if (!Files.isDirectory(dir)) return;
        try (DirectoryStream<Path> stream = Files.newDirectoryStream(dir, "*.json")) {
            for (Path order : stream) {
                String name = order.getFileName().toString();
                long blocks = countBlocks(order);
                mc.player.displayClientMessage(Component.literal(
                    "§d[lens]§r build order '" + name + "' received ("
                        + blocks + " placements) - control executor lands in v2.1"),
                    false);
                Path seen = dir.resolve("seen");
                Files.createDirectories(seen);
                Files.move(order, seen.resolve(name), StandardCopyOption.REPLACE_EXISTING);
                PaperclipLens.LOG.info("build order acknowledged: {} ({} blocks)",
                    name, blocks);
            }
        } catch (IOException e) {
            PaperclipLens.LOG.warn("orders poll failed: {}", e.toString());
        }
    }

    /** Cheap count of placement entries without a full JSON parse. */
    private static long countBlocks(Path file) {
        try {
            String text = Files.readString(file);
            long count = 0;
            int idx = -1;
            while ((idx = text.indexOf("\"b\"", idx + 1)) != -1) count++;
            return count;
        } catch (IOException e) {
            return 0;
        }
    }
}
